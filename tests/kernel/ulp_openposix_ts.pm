# SUSE's openQA tests
#
# Copyright 2025 SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Summary: Install glibc livepatch and run openposix testsuite
#          Use transactional-update command
# Maintainer: qe-core <qe-core@suse.com>

use strict;
use warnings;
use base 'opensusebasetest';
use testapi;
use utils;
use serial_terminal;
use klp;
use qam;
use LTP::utils;
use OpenQA::Test::RunArgs;
use version_utils;
use package_utils;

sub setup_ulp {
    my $packname = 'openposix-livepatches';
    my $repo_args = '';

    install_klp_product;
    install_package('in libpulp0 libpulp-tools');

    # Find glibc versions targeted by livepatch package
    my $provides = script_output("zypper -n info --provides $repo_args $packname");
    my @versions = $provides =~ m/^\s*libc_([^_()]+)_livepatch\d+\.so\(\)\([^)]+\)\s*$/gm;

    die "Package $packname contains no libc livepatches"
      unless scalar @versions;

    # Find which targeted glibc versions can be installed. Livepatch RPMs
    # get released for multiple SLE service packs and some old targeted glibc
    # versions may be unavailable on the newer service packs.
    my %glibc_map;
    my $glibc_versions = zypper_search('-s -x -t package glibc');

    $glibc_map{$$_{version}} = 1 for (@$glibc_versions);
    @versions = grep { defined($glibc_map{$_}) } @versions;
    die "No livepatchable glibc versions found" unless scalar @versions;

    prepare_ltp_env;
    return OpenQA::Test::RunArgs->new(run_id => 0,
        glibc_versions => \@versions, packname => $packname);
}

sub run {
    my ($self, $tinfo) = @_;

    select_serial_terminal;

    if (!defined($tinfo)) {
        # First test round in the job, prepare environment
        $tinfo = setup_ulp();

        # Incident has no userspace livepatch related packages, nothing to do
        return if not $tinfo;
    } else {
        zypper_call("rm " . $tinfo->{packname});
    }

    # Schedule openposix tests and install the livepatch
    my $libver = $tinfo->{glibc_versions}[$tinfo->{run_id}];
    record_info('glibc version', $libver);
    install_package("--oldpackage glibc-$libver");
    schedule_tests('openposix', "_glibc-$libver");
    #loadtest_kernel('ulp_threads', name => "ulp_threads_glibc-$libver",
    #    run_args => $tinfo);
    install_package($tinfo->{packname});

    # Run tests again with the next untested glibc version
    if ($tinfo->{run_id} < $#{$tinfo->{glibc_versions}}) {
        my $runargs = OpenQA::Test::RunArgs->new(run_id => $tinfo->{run_id} + 1,
            glibc_versions => $tinfo->{glibc_versions},
            packname => $tinfo->{packname});

        loadtest_kernel('ulp_openposix', run_args => $runargs);
    }
    else {
        shutdown_ltp;
    }
}

sub test_flags {
    return {
        fatal => 1,
        milestone => 1,
    };
}

=head1 Configuration

This test module is activated by LIBC_LIVEPATCH=1

=cut

1;
