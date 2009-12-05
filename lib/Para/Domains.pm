# -*-cperl-*-
package Para::Domains;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se Domains
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2006-2009 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;
use warnings;

use Data::Dumper;
use Carp qw( confess );

BEGIN
{
    # Export before pulling in more modules
    #
    use constant DB_DOMAINS => "$WA::APPROOT/var/domains.db";
    use constant DB_DIR => "$WA::APPROOT/var/domains/";

    use base 'Exporter';
    use vars qw( @EXPORT_OK %EXPORT_TAGS );
    @EXPORT_OK = ( 'DB_DOMAINS', 'DB_DIR' );
    %EXPORT_TAGS = ('all' => ['DB_DOMAINS', 'DB_DIR']);
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( paraframe_dbm_open debug );

use Para::Domain;

use base 'Para::Frame::List';

our $INITIATED;

# TODO: Sync properly with Para::Frame::List

sub init
{
    my( $ds ) = @_;

    if( $INITIATED )
    {
	confess "Catched a second initiation of the domains list";
    }

    my $db = paraframe_dbm_open( DB_DOMAINS );
    debug "Opening domain list";

    $ds->{by_id} = {};
    $ds->{not_in_dbm} = [];
    my $by_id   = $ds->{by_id};
    my $not_in_dbm = $ds->{not_in_dbm};

    my @list;
    foreach my $name ( sort keys %$db )
    {
	utf8::upgrade($name);
	my $type = $db->{$name};
	my $d = Para::Domain->new( $name, $type, 1 );
	push @list, $d;
	$by_id->{$name} = $d;
    }

    foreach my $rec ( $Para::dbix->select_list("from domain")->as_array )
    {
	my $name = $rec->{'domain'};
	unless( $by_id->{$name} )
	{
	    my $d = Para::Domain->new( $name, $rec, 0 );
	    push @$not_in_dbm, $d;
	    push @$ds, $d;
	    $by_id->{$name} = $d;
	}
    }

    $ds->{'_DATA'} = \@list;

    $INITIATED ++;
}

sub get
{
    my( $ds, $name ) = @_;
    if( my $d = $ds->hashref->{'by_id'}{$name} )
    {
	return $d;
    }
    else
    {
	debug "Domain $name not found";
	return undef;
    }
}

sub types
{
    return \@Para::Domain::DOMAIN_TYPE;
}

sub types_as_hash
{
    return { map{$_=>$Para::Domain::DOMAIN_TYPE[$_]} 0..$#Para::Domain::DOMAIN_TYPE };
}

sub get_all
{

    # Reimplement this since we will usually not reset the
    # counter. Thus we will always give all the data. Not just the
    # rest, from where we left of previously;

    return [@{$_[0]}];
}

1;
