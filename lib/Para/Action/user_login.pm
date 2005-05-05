#  $Id$  -*-perl-*-
package Para::Action::user_login;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se user login action
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;

use Para::Member;
use Para::Frame::Utils qw( throw passwd_crypt );

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;

    # Validation
    #
    my $username = $q->param('username')
	or throw('incomplete', "Namn saknas\n");
    my $password = $q->param('password') || "";
    my $remember = $q->param('remember_login') || 0;

    my @extra = ();
    if( $remember )
    {
	push @extra, -expires => '+10y';
    }

    my $u = Para::Member->get_by_nickname( $username, 0 );
    $u or throw('validation', "Medlemmen $username existerar inte");
    
    Para::Member->change_current_user( $u );

    my $password_encrypted = passwd_crypt( $password );

    if( Para::Member->authenticate_user( $password_encrypted ) )
    {
	$req->cookies->add({
	    'username' => $username,
	    'password' => $password_encrypted,
	},{
	    @extra,
	});

	$q->delete('username');
	$q->delete('password');

	Para::Frame->run_hook('user_login');

	return "$username loggar in";
    }

    return "Inloggningen misslyckades\n";
}

1;
