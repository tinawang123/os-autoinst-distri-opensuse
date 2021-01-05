# SUSE's openQA tests
#
# Copyright © 2012-2020 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.
#
# Summary: samba test conecting with Active Directory using adcli
# package: samba adcli samba-winbind krb5-client
#
# Maintainer: Marcelo Martins <mmartins@suse.com>

use strict;
use warnings;
use base "consoletest";
use repo_tools qw(add_qa_head_repo add_qa_web_repo);
use testapi;
use utils;

sub run {
    my $self = shift;
    select_console 'root-console';
    #$self->select_serial_terminal;

    systemctl('status smb nmb winbind');
    #systemctl('restart nmb');
    #systemctl('restart winbind');
    #Verify users and groups  from AD
    assert_script_run "wbinfo -u";
    assert_script_run "wbinfo -g";
    assert_script_run "wbinfo -D geeko.com";
    assert_script_run "wbinfo -i geekouser\@geeko.com";
    assert_script_run "wbinfo -i Administrator\@geeko.com";
}

1;
