#  $Id$  -*-perl-*-
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
#   Copyright (C) 2004 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Email::Address

=cut

use strict;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw );

use base 'Para::Frame::Email::Address';

sub validate
{
    my( $a, $m ) = @_;

    my $astr = $a->address;

    if( $astr =~ /^(.*?)\@paranormal\.se$/ )
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

    return $a->SUPER::validate or $m->change->fail($a->error_msg);
}

######################################################################

1;
