#  $Id$  -*-perl-*-
package Para::Arctype;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se arcs arctype class
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

use Para::Frame::Reload;
use Para::Frame::Time qw( now );

use Para::Topic;

sub new
{
    # Get relation(s) matching the params
    #
    my( $this, $rec ) = @_;
    my $class = ref($this) || $this;

    my $name = $rec;

    if( ref $rec eq 'HASH' )
    {
	# Assume its the DB record
    }
    elsif( $rec =~ /^\d+$/ )
    {
	$rec = $Para::dbix->select_record("from reltype where reltype=?", $rec);
    }
    else
    {
	$rec = $Para::dbix->select_possible_record("from reltype where lower(rel_name)=lower(?) or lower(rev_name)=lower(?)", $rec, $rec);
    }

    unless( ref $rec eq 'HASH' )
    {
	die "Arctype '$name' doesn't exist\n";
    }


    return bless( $rec, $class );
}

sub list
{
    my( $class, $crits ) = @_;

    my @list = ();
    my $recs;

    if( $crits )
    {
	if( ref $crits eq 'ARRAY' )
	{
	    $recs = $crits;
	}
	elsif( $crits eq 'literals' )
	{
	    $recs = $Para::dbix->select_list('from reltype where reltype_literal is true order by reltype');
	}
	else
	{
	    die "Method not implemented: $crits";
	}
    }
    else
    {
	$recs = $Para::dbix->select_list('from reltype order by reltype');
    }

    foreach my $rec (@$recs)
    {
	push @list, $class->new( $rec );
    }

    return \@list;
}

sub create
{
    my( $class ) = @_;

    my $m = $Para::Frame::U;

    my $id = get_nextval( "reltype_seq" );

    my $sth_reltype = $Psi::dbh->prepare_cached(
	  "insert into reltype (reltype, reltype_updated, reltype_changedby)
           values ( ?, now(), ? )");
    $sth_reltype->execute($id, $m->id) or die;

    return Para::Arctype->new( $id );
}

sub update
{
    my( $at, $rec_in ) = @_;

    my $rec_new =
    {
	'rel_name'            => $rec_in->{'rel_name'},
	'rev_name'            => $rec_in->{'rev_name'},
	'reltype_super'       => $rec_in->{'super'},
	'reltype_topic'       => $rec_in->{'topic'},
	'reltype_description' => $rec_in->{'description'},
	'reltype_literal'     => $rec_in->{'literal'},
    };

    my $types =
    {
	'reltype_literal'     => 'boolean',
    };

    return $Para::dbix->save_record({
	rec_new => $rec_new,
	rec_old => $at,
	table   => 'reltype',
	keyval  => $at->id,
	types   => $types,
	on_update =>
	{
	    reltype_updated   => now()->cdate,
	    reltype_changedby => $Para::Frame::U->id,
	},
    });
}

sub name
{
    my( $type, $dir ) = @_;
    if( $dir eq 'rel' )
    {
	return $type->{'rel_name'};
    }
    elsif( $dir eq 'rev' )
    {
	return $type->{'rev_name'};
    }
    elsif( not defined $dir )
    {
	croak "No direction specified for arc.name(dir)\n";
    }
    else
    {
	croak "What kind of direction do you think that $dir is?!?";
    }
}

sub rel_name { $_[0]->{'rel_name'} }
sub rev_name { $_[0]->{'rev_name'} }
sub literal  { $_[0]->{'reltype_literal'} }
sub id       { $_[0]->{'reltype'} }

sub topic    { Para::Topic->get_by_id( $_[0]->{'reltype_topic'} ) }

sub super
{
    return undef unless $_[0]->{'reltype_super'};
    return Para::Arctype->new($_[0]->{'reltype_super'});
}

sub description
{
    $_[0]->{'reltype_description'};
}

1;
