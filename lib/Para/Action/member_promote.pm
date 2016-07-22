# -*-cperl-*-
package Para::Action::member_promote;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se member promote action
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

sub handler
{
	my( $req ) = @_;

	my $u = $Para::Frame::U;

	# Promote user if this is the first login
	#
	if ( $u->level == 1 )
	{
		my $sys = Para::Member->get(-1);
		$u->level( 2, $sys );
		$req->set_page("/member/db/person/quest/level_02/welcome.tt");
		return "Nivå 2";
	}

	return "Ingen ändring av nivån";
}

1;
