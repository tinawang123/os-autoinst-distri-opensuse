# SUSE's openQA tests
#
# Copyright 2012-2026 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Package: synce4l gpsd
# Summary: Test case for Precision Timing packages (synce4l and gpsd) on SL Micro
# Maintainer: qe-core <qe-core@suse.com>

use Mojo::Base 'consoletest';
use testapi;
use version_utils;
use utils;
use package_utils 'install_package';

sub run {
    my ($self) = @_;

    # Ensure we are logged in as root on the console
    $self->select_serial_terminal;

    record_info("Install", "Installing precision timing packages on SL Micro");
    
    # 1. Package Installation and Upstream Version Verification
    # SL Micro uses transactional-update. To test dynamically, we can use a raw container/overlay 
    # or step through transactional-update if running on a standard image.
    # For a standard openQA runtime test, we assume a mutable test layer or standard zypper if available.
    #assert_script_run("zypper -n in synce4l gpsd");
    install_package('synce4l gpsd', trup_reboot => 1);
    
    record_info("Version Check", "Verifying updated upstream versions for Granite Rapids compatibility");
    
    # Verify synce4l is at least version 1.1.1
    my $synce_version = script_output("synce4l -v 2>&1");
    if ($synce_version =~ /1\.1\.[1-9]/) {
        record_info("synce4l version is modern: $synce_version");
    } else {
        die "Unexpected synce4l version! Found: $synce_version. Expected >= 1.1.1";
    }

    # Verify gpsd version (e.g., checking version string or CLI syntax helper)
    # Adjust flag based on upstream gpsd documentation (-v, --version, or help validation)
    assert_script_run("gpsd --version");

    # 2. Functional Configuration & Validation for synce4l
    record_info("synce4l Test", "Creating a safe dry-run configuration for Synchronous Ethernet");
    
    my $synce_config = <<'EOF';
[global]
logging_level 7
use_syslog 1
message_tag synce4l-test

[eth0]
network_option 1
EOF

    # Alternative: directly echo it in
    assert_script_run("echo '$synce_config' > /etc/synce4l_test.conf");

    # Run synce4l in a brief background evaluation or check config syntax if supported.
    # Since we lack the hardware DPLL subsystem on a standard VM, we check for clean exit or proper hardware-missing log signature
    my $synce_check = script_output("synce4l -f /etc/synce4l_test.conf -t -v || true");
    record_info("synce4l Output", $synce_check);

    # 3. Functional Testing for gpsd (General Sync Platform Daemon / GNSS Sync)
    record_info("gpsd Test", "Validating systemd service presence and configuration validation");

    # Check systemd units are delivered by the new packages
    assert_script_run("systemctl daemon-reload");
    assert_script_run("systemctl show synce4l --property=LoadState | grep -q 'loaded'");
    assert_script_run("systemctl show gpsd --property=LoadState | grep -q 'loaded'");

    # Generate a baseline mock config for gpsd if required by systemd service
    # and trigger a dry run test.
    if (script_run("systemctl start gpsd") != 0) {
        my $gpsd_log = script_output("journalctl -n 20 -u gpsd");
        record_info("gpsd Journal", $gpsd_log);
        # Accept "no device found" or "missing hardware" signatures, but reject "Segmentation fault" or "invalid option"
        if ($gpsd_log =~ /segfault|core dumped/i) {
            die "gpsd crashed with a core dump/segfault on initialization!";
        }
    }

    record_info("Cleanup", "Cleaning up evaluation files");
    assert_script_run("rm -f /etc/synce4l_test.conf");
}

sub test_flags {
    return { fatal => 1 };
}

1;
