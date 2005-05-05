#  $Id$  -*-perl-*-
package Para::Email;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se Email extension class
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

Para::Email - Sending emails

=cut

use strict;
use vars qw( $VERSION );

BEGIN
{
    $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;

use base 'Para::Frame::Email';

sub set
{
    my( $e, $p ) = @_;

    # Can be called multipple times

    $p = $e->SUPER::set( $p );

    $p->{'from'} ||= '"Paranormal.se" <info@paranormal.se>';
    $p->{'subject'} ||= 'Info från Paranormal.se';

    unless( $p->{'to'} )
    {
	if( my $m = $p->{'m'} )
	{
	    my @try = $m->sys_email;
	    foreach my $email ( $m->mailaliases )
	    {
		push @try, $email unless $email eq $try[0];
	    }
	    $p->{'to'} = \@try;
	}
    }

    return $p;
}

sub send
{
    my( $e, @args ) = @_;

    my $res = $e->SUPER::send( @args );

    foreach my $email ( $e->good )
    {
	# TODO: Note success
    }

    foreach my $email ( $e->bad )
    {
	# TODO: Note failure
    }

    return $res;
}

1;
