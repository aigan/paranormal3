#  $Id$  -*-perl-*-
package Para::Change;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se DB Change class
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

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;

sub new
{
    my( $class ) = @_;
    my $self =
    {
	errors => 0,
	errmsg => "",
	changes => 0,
	message => "\n",
     };

    return bless $self, $class;
}

sub success
{
    my( $change, $msg ) = @_;
    $msg =~ s/\n?$/\n/; # Add if missing
    $change->{'changes'} ++;
    $change->{'message'} .=  $msg;
    return 1;
}

sub note
{
    my( $change, $msg ) = @_;
    $msg =~ s/\n?$/\n/; # Add if missing
    $change->{'message'} .=  $msg;
    return 1;
}

sub fail
{
    my( $change, $msg ) = @_;
    $msg =~ s/\n?$/\n/; # Add if missing
    $change->{'errors'} ++;
    $change->{'errmsg'} .=  $msg;
    return undef;
}

sub changes
{
    return $_[0]->{'changes'};
}

sub errors
{
    return $_[0]->{'errors'};
}

sub message
{
    return $_[0]->{'message'};
}

sub errmsg
{
    return $_[0]->{'errmsg'};
}

1;
