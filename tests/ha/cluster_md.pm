# SUSE's openQA tests
#
# Copyright 2017-2018 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Package: mdadm
# Summary: cluster-md tests
# Maintainer: QE-SAP <qe-sap@suse.de>, Loic Devulder <ldevulder@suse.com>

use base 'haclusterbasetest';
use strict;
use warnings;
use version_utils 'is_sle';
use testapi;
use lockapi;
use hacluster;

sub run {
    my $mdadm_conf = '/etc/mdadm.conf';
    my $clustermd_lun_01 = get_lun(use_once => 0);
    my $clustermd_lun_02 = get_lun(use_once => 0);
    my $clustermd_rsc = 'cluster_md';
    my $clustermd_device = '/dev/md0';
    my $clustermd_name_opt = undef;
    my $cluster_name = get_cluster_name;
    my $node = get_hostname;

    if (is_sle '15+') {
        $clustermd_device = "/dev/md/$clustermd_rsc";
        $clustermd_name_opt = "--name=$clustermd_rsc";
    }

    # Wait until cluster-md test is initialized
    barrier_wait("CLUSTER_MD_INIT_$cluster_name");

    # Test if DLM kernel module package is installed
    die 'cluster-md kernel package is not installed' unless is_package_installed 'cluster-md-kmp-default';

    # DLM process/resource needs to be started
    ensure_dlm_running;

    if (is_node(1)) {
        # Create cluster-md device
        assert_script_run
"mdadm --create $clustermd_device $clustermd_name_opt --bitmap=clustered --metadata=1.2 --raid-devices=2 --level=mirror \"$clustermd_lun_01\" \"$clustermd_lun_02\"", $default_timeout;

        # We need to create the configuration file on all nodes
        assert_script_run "echo DEVICE $clustermd_lun_01 $clustermd_lun_02 > $mdadm_conf", $default_timeout;
        assert_script_run "mdadm --detail --scan >> $mdadm_conf", $default_timeout;

        # We need to add the configuration in csync2.conf
        add_file_in_csync(value => "$mdadm_conf");
    }
    else {
        diag 'Wait until cluster-md device is created...';
    }

    # Wait until cluster-md device is created
    barrier_wait("CLUSTER_MD_CREATED_$cluster_name");

    if (is_node(1)) {
        # Create cluster-md resource
        assert_script_run
"EDITOR=\"sed -ie '\$ a primitive $clustermd_rsc ocf:heartbeat:Raid1 params raiddev=auto force_clones=true raidconf=$mdadm_conf'\" crm configure edit", $default_timeout;
        assert_script_run "EDITOR=\"sed -ie 's/^\\(group base-group.*\\)/\\1 $clustermd_rsc/'\" crm configure edit", $default_timeout;
    }
    else {
        diag 'Wait until cluster-md resource is created...';
    }

    # Wait until cluster-md resource is created
    barrier_wait("CLUSTER_MD_RESOURCE_CREATED_$cluster_name");

    # Wait for the resource to appear before testing the device
    # Otherwise sporadic failure can happen
    ensure_resource_running("$clustermd_rsc", "is running on:[[:blank:]]*$node\[[:blank:]]*\$");

    # Test if cluster-md device is present on all nodes
    # Sometimes in high performance virtual scenarios, it takes some seconds for the cluster_md
    # device to be present in /dev, so this will check for some number of tries before failing
    check_device_available($clustermd_device);

    # Wait until R/W state is checked
    barrier_wait("CLUSTER_MD_CHECKED_$cluster_name");

    # Do a check of the cluster with a screenshot
    save_state;

    # Add the tag for resource configuration
    write_tag("$clustermd_rsc");
}

1;
