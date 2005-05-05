#  $Id$  -*-perl-*-
package Para::Interest;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se Member interest class
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
use Carp qw(cluck);
use locale;
use Date::Manip;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( trim throw );
use Para::Arcs;


######## Constructor

sub new
{
    my( $this, $rec ) = @_;
    my $class = ref($this) || $this;

    unless( UNIVERSAL::isa($rec, 'HASH' ) )
    {
	die "not implemented:".Dumper($rec);
    }

    return bless $rec, $class;
}

sub get
{
    my( $this, $m, $t ) = @_;

    $m = Para::Member->get( $m );
    unless( ref $t )
    {
	$t = Para::Topic->find_one( $t );
    }

    warn "  Creating Interest object\n";
#    cluck Dumper[$this,$m,$t];

    my $rec = $Para::dbix->select_possible_record('from intrest where intrest_member=? and intrest_topic=? and intrest_defined >= 10 and intrest is not null order by intrest desc, intrest_defined desc', $m->id, $t->id );

    return undef unless $rec;
#    warn Dumper $rec;
    return $this->new( $rec );    
}

######## Methods

sub topic
{
    my( $intr ) = @_;

    return Para::Topic->new( $intr->{'intrest_topic'} );
}

sub general
{
    return $_[0]->{'intrest'};
}

sub comment
{
    return $_[0]->{'intrest_description'};
}

sub defined
{
    return $_[0]->{'intrest_defined'};
}

sub equals
{
    my( $intr1, $intr2 ) = @_;

    if( $intr1->{'intrest_member'} == $intr2->{'intrest_member'} and
	$intr1->{'intrest_topic'} == $intr2->{'intrest_topic'} )
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
    die "not implemented";
}

###################  Class static methods

sub touch
{
    my( $this, $t, $m, $defined ) = @_;
    my $class = ref($this) || $this;
    $m ||= $Para::u;
    $t or throw('incomplete', "t missing\n");
    $defined ||= 1;

    my $mid = ref $m ? $m->id : $m;
    my $tid = ref $t ? $t->id : $t;

    my $st_find = "select * from intrest where intrest_topic=? and intrest_member=?";
    my $sth_find = $Para::dbh->prepare_cached( $st_find );
    $sth_find->execute( $tid, $mid );
    my $rec = {};
    if( $sth_find->rows == 0)
    {
	Para::Interest->create( $t, $m, $defined );
    }
    $sth_find->finish;
    return 1;
}


sub create
{
    my( $this, $t, $m, $defined ) = @_;
    my $class = ref($this) || $this;
    $m ||= $Para::u;
    $t or throw('incomplete', "t missing\n");
    $defined ||= 1;

    my $mid = ref $m ? $m->id : $m;
    my $tid = ref $t ? $t->id : $t;

    if( $Para::u->level < 40 and $Para::u->id != $mid )
    {
	throw('denied', "Du har inte access för att ändra någon annans intressen.");
    }


    my $sth = $Para::dbh->prepare_cached("insert into intrest
             ( intrest_member, intrest_topic, intrest_updated, intrest_defined )
                                         values ( ?, ?, now(), ?)");
    eval
    {
	$sth->execute( $mid, $tid, $defined );
    };
    if( $@ )
    {
	if( $Para::dbh->errstr =~ /duplicate key/ )
	{
	    throw('create', "This intrest already exists\n");
	}
	die;
    }

    return 1;
}

1;
