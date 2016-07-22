# -*-cperl-*-
package Para::Domain;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se Domain
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

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw paraframe_dbm_open debug );

use Para::Domains qw( :all );
use Para::Email::Redirect;


### INITIALIZE
#
our @DOMAIN_TYPE  =
	("Undefined",
	 "Reserverad",
	 "Normal",
	 "Namndomän",
	);

sub new
{
	my( $this, $name, $type, $in_dbm ) = @_;
	my $class = ref($this) || $this;

	$in_dbm ||= 0;

	my $rec;
	if ( ref $type )
	{
		$rec = $type;
		$rec->{in_rdb} = 1;
		$rec->{in_dbm} = $in_dbm;
	}
	else
	{
		$rec = $Para::dbix->select_possible_record("from domain where domain=?",$name);

		if ( $rec )
		{
	    if ( $type and $type != $rec->{'domain_type'} )
	    {
				debug "Domain $name type mismatch ($rec->{domain_type} != $type)";
	    }

	    $rec->{in_rdb} = 1;
	    $rec->{in_dbm} = $in_dbm;
		}
		else
		{
	    $rec =
	    {
			 in_rdb => 0,
			 in_dbm => 1,
			 domain => $name,
			 domain_type => $type,
	    };
		}
	}

	return bless $rec, $class;
}

sub get
{
	die "deprecated";
	my( $this, $id ) = @_;
	my $class = ref($this) || $this;

	my $db = paraframe_dbm_open( DB_DOMAINS );
	my $name = $id;
	my $type = $db->{$id} or throw("not found", "Can't find domain $id");
	return $this->new( $name, $type );
}

sub create
{
	die "not implemented";

	my( $this, $name, $type ) = @_;

	my $class = ref($this) || $this;
	my $db = paraframe_dbm_open( DB_DOMAINS );

	$db->{ $name } = $type;
	return $this->new( $name, $type );
}

#########################################

sub id
{
	my( $d ) = @_;
	return $d->{'domain'};
}

sub name
{
	my( $d ) = @_;
	return $d->{'domain'};
}

sub type
{
	my( $d ) = @_;
	return $d->{'domain_type'};
}

sub type_name
{
	my( $d ) = @_;

	return $DOMAIN_TYPE[ $d->{'domain_type'} ];
}

sub redirects
{
	my( $d ) = @_;

	return $d->{'redirects'} || $d->redirects_init;
}

sub redirects_init
{
	my( $d ) = @_;

	if ( $d->{'redirects'} )
	{
		confess "Called twice";
	}

	my $by_alias = $d->{'r_by_alias'} = {};
	my $by_id = $d->{'r_by_id'} = {};

	my $db = $d->db;
	my @redirects;
	foreach my $alias ( keys %$db )
	{
		my $dest = $db->{$alias};
		my $r = Para::Email::Redirect->new( $d, $alias, $dest, 1 );
		push @redirects, $r;
		$by_alias->{$alias} = $r;
		if ( $r->id )
		{
	    $by_id->{$r->id} = $r;
		}
	}

	foreach my $rec ( $Para::dbix->select_list("from mailr
                      where mailr_domain=?", $d->name)->as_list )
	{
		my $alias = $rec->{'mailr_name'};
		unless ( $by_alias->{$alias} )
		{
	    my $r = Para::Email::Redirect->new( $d, $alias, $rec, 0 );
	    push @redirects, $r;
	    $by_alias->{$alias} = $r;
	    $by_id->{$r->id} = $r;
		}
	}

	my @sorted = sort{ lc($a->alias) cmp lc($b->alias) } @redirects;

	return $d->{'redirects'} = Para::Frame::List->new(\@sorted);
}

sub redirect
{
	my( $d, $alias ) = @_;

	debug "Looking up redirect for $alias";

	$alias or throw('incomplete',"Redirect method called without alias param");
	$d->{'redirects'} or $d->redirects_init;
	return $d->{'r_by_alias'}{$alias} || $d->{'r_by_id'}{$alias} or
		die "Redirection $alias not found";
}

sub db_filename
{
	my( $d ) = @_;

	return  DB_DIR . $d->name;
}

sub db
{
	my( $d ) = @_;

	return paraframe_dbm_open( $d->db_filename );
}

sub in_rdb
{
	return $_[0]->{'in_rdb'};
}

sub in_dbm
{
	return $_[0]->{'in_dbm'};
}

#########################################

sub add_in_dbm
{
	my( $d ) = @_;

	my $name = $d->name;
	my $type = $d->type;

	my $db = paraframe_dbm_open( DB_DOMAINS );

	$db->{ $name } = $type;

	$d->{'in_dbm'} = 1;
	return 1;
}

sub add_in_rdb
{
	my( $d ) = @_;

	my $name = $d->name;
	my $type = $d->type;

	if ( $d->in_rdb )
	{
		return 0;										# Already existing
	}

	my $uid = $Para::Frame::U->id;

	$Para::dbix->insert({
											 table => 'domain',
											 rec =>
											 {
												domain => $name,
												domain_type => $type,
												domain_updatedby => $uid,
											 },
											});

	$d->{'in_rdb'} = 1;
	return 1;
}

sub email_create
{
	die "not implemented";

	my( $d, $alias, $email ) = @_;

	Para::Email::Redirect->create( $d, $alias, $email );
}

sub remove
{
	die "not implemented";

	my( $d ) = @_;

	my $file = $d->db_filename;
	unlink $file or die "Failed to remove file $file: $!\n";

	my $db = paraframe_dbm_open( DB_DOMAINS );
	my $name = $d->name;
	delete( $db->{$name} );
	return 1;
}

sub set_type
{
	die "not implemented";

	my( $d, $type ) = @_;

	die if $type < 1;
	die if $type > 3;

	my $db = paraframe_dbm_open( DB_DOMAINS );
	my $name = $d->name;
	$db->{$name} = $type;
}

1;
