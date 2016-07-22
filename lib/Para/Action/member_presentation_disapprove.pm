# -*-cperl-*-
package Para::Action::member_presentation_disapprove;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se disapprove member presentation
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

use Para::Frame::Utils qw( throw debug );

use Para::Member;

sub handler
{
	my( $req ) = @_;

	my $u = $Para::Frame::U;
	my $q = $req->q;

	if ( $u->level < 12 )
	{
		throw('denied', "Du har inte access för att ändra någon annan.");
	}

	my $mid = $q->param('mid') or die "Member param missing\n";

	my $m = Para::Member->get( $mid );

	# This will not catch race conditions
	unless( $m->level == 3 )
	{
		throw('validation', sprintf("Försent. %s är nivå %d nu.\n", $m->desig, $m->level));
	}

	$m->changes->reset;
	$m->update_by_query;

	my $fork = Para::Email->send_by_proxy({
																				 subject => "Presentationen är inte klar",
																				 m => $m,
																				 template => 'member_presentation_disapprove.tt',
																				});

#    # Wait until e-mail got delivierd
#    ### $fork = Para::Email->send_in_fork(...);
#    $fork->yield;
#    return "Aborted" if $fork->failed;
#    $req->result->message(sprintf "E-post har skickats till %s.", $m->desig);

	$m->level( 2, Para::Member->skapelsen ); # Update member level

	$m->changes->report;

	$u->score_change('demoted_user', 1);

	return "Skickar brevet i bakgrunden";
}

1;
