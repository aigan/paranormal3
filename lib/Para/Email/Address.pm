# -*-cperl-*-
package Para::Email::Address;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se Email Address class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2009 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Email::Address

=cut

use strict;
use warnings;

use Carp qw( confess );

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw );

use base 'Para::Frame::Email::Address';

sub validate
{
	my( $a, $m ) = @_;

	my $astr = $a->address;
	$m or confess "m param missing";

	if ( $astr =~ /^(.*?)\@paranormal\.se$/ )
	{
		my $nick = $1;

		$m->sys_uid or return $m->change->fail
			("Du har inte en postlåda här\n");

		unless( $m->has_nick( $nick ) )
		{
	    return $m->change->fail("Du kan inte skicka posten ".
															"till någon annan\n");
		}
	}

	# This construct was created because the SUPER::validate would
	# throw an exception that doesn't has the $@ set. Maby this is a
	# bug with SUPER. -- We check the $res and constructs the failure
	# massage in any case.

	my $res;
	eval
	{
		$res = $a->SUPER::validate;
	};
	die $@ if $@;
	return $res if $res;

	return $m->change->fail($a->error_msg); # error
}

######################################################################

1;
