# -*-cperl-*-
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
#   Copyright (C) 2004-2009 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Email - Sending emails

=cut

use strict;
use warnings;

use Para::Frame::Reload;

use Para::Frame::Utils qw( debug in datadump );

use base 'Para::Frame::Email::Sending';

sub set
{
	my( $e, $p ) = @_;

	# Can be called multipple times

	$p = $e->SUPER::set( $p );

	my $from = $p->{'from'} ||= '"Paranormal.se" <info@paranormal.se>';
	$p->{'subject'} ||= 'Info från Paranormal.se';

	unless( ref $from )
	{
		$from = Para::Email::Address->parse( $from );
	}

	if ( $p->{'m'} )
	{

		# Removing previous recipient in case the $e object is reused
		# for sending to a list of reciepients

		delete $p->{'to'};
	}

	unless ( $p->{'to'} )
	{
		if ( my $m = $p->{'m'} )
		{
	    my @try = $m->sys_email;
	    foreach my $email ( $m->mailaliases )
	    {
				push @try, $email unless $email eq $try[0];
	    }
	    $p->{'to'} = \@try;
		}
	}

	# If the sender isn't one of our authorative domains..:
	my @domains = qw( paranormal.se para.se );
	my $host = $from->host;

	## Setting a correct sender if this is not the home domain
	unless( in $host, @domains )
	{
		debug "$host is not one of @domains";
    
		my $desig = $from->desig;

		$p->{'envelope_from'} = "bounce\@paranormal.se";
		$p->{'sender'} = "\"$desig via paranormal.se\" <bounce\@paranormal.se>";
	}

	$p->{'from'} = $from;

	return $p;
}

sub send
{
	my( $e, @args ) = @_;

	$e = $e->new unless ref $e;
	my $res = $e->SUPER::send( @args );

	$e->handle_result;
	return $res;
}

sub handle_result
{
	my( $e ) = @_;

	foreach my $email ( $e->good )
	{
		debug(0,"$email is good");
		# TODO: Note success
	}

	foreach my $email ( $e->bad )
	{
		debug(0,"$email is bad");
		# TODO: Note failure
	}
}

1;
