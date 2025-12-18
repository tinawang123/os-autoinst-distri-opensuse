# SUSE's openQA tests
#
# Copyright 2024 SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Summary: Verify ULP redirection to /var/livepatches on transactional systems
# Maintainer: qe-core <qe-core@suse.com>

use base 'opensusebasetest';
use testapi;
use utils;
use serial_terminal;
use version_utils;
use package_utils;

sub run {
    my ($self) = @_;
    select_serial_terminal;

    # Ensure we are on a transactional system
    die "This test is intended for transactional systems only" unless is_transactional();

    my $patch_pkg = get_var('ULP_PATCH_PACKAGE', 'glibc-livepatches');
    
    # Check initial state: echo should link to standard /lib64/libc.so.6
    record_info('Initial State', 'Checking ldd output before livepatch installation');
    validate_script_output('ldd $(which echo)', sub { $_ !~ m|/var/livepatches/| });

    # Install the livepatch package
    record_info('Install Patch', "Installing $patch_pkg");
    install_package($patch_pkg, trup_continue => 1, trup_reboot => 1);

    # ULP tools should add the ld.so.conf entry to prioritize /var/livepatches
    record_info('Verify Config', 'Checking /etc/ld.so.conf for ULP inclusion');
    validate_script_output('cat /etc/ld.so.conf', qr|^include\s+/var/livepatches/ld\.so\.conf$|m);

    # Verification: New processes must load libc from /var/livepatches/
    record_info('Verify Redirection', 'Checking if echo loads libc from /var/livepatches/');
    
    # The regex looks for libc.so mapping to the livepatch path
    my $ldd_regex = qr(libc\.so\.\d+\s+=>\s+/var/livepatches/.*libc\.so\.\d+)m;
    validate_script_output('ldd $(which echo)', $ldd_regex);

    # Functional check: Ensure a basic command still runs correctly
    validate_script_output('echo "ULP Redirection Success"', qr/ULP Redirection Success/);
}

sub test_flags {
    return {
        fatal => 1,
        milestone => 1,
    };
}

1;
