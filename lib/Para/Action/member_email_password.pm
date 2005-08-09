#  $Id$  -*-perl-*-
package Para::Action::member_email_password;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se member email password action
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
use Data::Dumper;

use Para::Frame::Utils qw( throw );

use Para::Email;
use Para::Member;

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;

    my $nick = $q->param('nick') or die "Nick param missing\n";

    my $mlist = Para::Member->by_name( $nick );

    unless( @$mlist )
    {
	throw('notfound', "Hittar inte medlemmen $nick");
    }
    if( @$mlist > 1 )
    {
	throw('alternatives', "Flera medlemmar matchade din sökning");
    }

    my $m = $mlist->[0]; # Get the only result
    my $e = Para::Email->new;
    $e->set({
	subject => "Lösenord till Paranormal.se",
	m => $m,
	template => 'password_reminder.tt',
    });

    my $fork = $req->create_fork;
    if( $fork->in_child )
    {
	# Become root in order to get access to passwords
	Para::Member->become_root;
	$e->send or throw('email', $e->error_msg);
	Para::Member->revert_from_root;
	$fork->return("E-post med lösenordet har nu skickats till minst en av adresserna för $nick.\n");
      }

    return "";
}

1;
