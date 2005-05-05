#  $Id$  -*-perl-*-
package Para::Place;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se Place class
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
use Carp;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Utils qw( trim throw );
use Para::Constants qw( :all );

sub new
{
    my( $this, $type, $rec, $no_cache ) = @_;
    my $class = ref($this) || $this;
    # $rec can be provided as a mean for optimization

    confess "type param missing" unless $type;
    confess "rec param missing" unless $rec;

    my( $id, $p );

    if( $rec =~ /^\d+$/ )
    {
	$id = $rec;
	$rec = undef;
    }

    if( not $no_cache or not $rec )
    {
	if( exists $Para::Place::CACHE->{type}{$id} )
	{
	    return $Para::Place::CACHE->{type}{$id};
	}
    }

    unless( $rec )
    {
	my $st = "select * from $type where $type=?";
	my $sth = $Para::dbh->prepare_cached( $st );
	$sth->execute( $id );
	$rec =  $sth->fetchrow_hashref;
	$sth->finish;
    }

    if( $rec )
    {
	$p = $Para::Place::CACHE->{$id} = bless($rec, $class);
    }
    else
    {
	$p = $Para::Place::CACHE->{$id} = undef;
    }

    $p->{'geo_x'} = $p->{$type.'_x'};
    $p->{'geo_y'} = $p->{$type.'_y'};

    return $p;
}

sub geo_x
{
    my( $m ) = @_;
    return $m->{'geo_x'};
}

sub geo_y # ;;;
{
    my( $m ) = @_;
    return $m->{'geo_y'};
}

sub equals
{
    my( $p, $p2 ) = @_;

    return 0 unless ref $p2;
    return 0 unless $p->type eq $p2->type;

    if( $p->id == $p2->id )
    {
	return 1;
    }
    else
    {
	return 0;
    }
}

sub desig
{
    my( $p ) = @_;

    return $p->name;
}

sub name
{
    my( $p ) = @_;

    return $p->{'name'};
}

#################################################################

sub by_name  ## LIST CONSTRUCTOR
{
    my( $this, $identity, $complete ) = @_;
    my $class = ref($this) || $this;

    my @places;

    trim( \$identity );
    $identity = lc( $identity );

    my $found = 0;

    if( $identity eq 'här' )
    {
	$identity = $Para::u->home_postal_code;
    }

    if( $identity =~ m/^(s-)?[\d\s]+$/i ) # Zip code
    {
	$identity =~ s/\D//g;
	push @places, $this->new('zip', $identity);
    }
    else # City
    {
	if( my $rec = $Para::dbix->select_possible_record("from city where lower(city_name)=?", $identity) )
	{
	    push @places, $this->new('city', $rec);
	}

	if( $complete or not $found )
	{
	    # Add county search
	}

	if( $complete or not $found )
	{
	    # add other search...
	}
    }

    my @sorted = sort { lc($a->{'name'}) cmp lc($b->{'name'}) } @places;

    return \@sorted;
}

1;
