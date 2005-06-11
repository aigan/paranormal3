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
use Para::Member;
use Para::Topic;

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

    warn "  get interest $t->{id}\n";
#    cluck Dumper[$this,$m,$t];

    my $rec = $Para::dbix->select_possible_record('from intrest where intrest_member=? and intrest_topic=? and intrest_defined >= 10 and intrest is not null order by intrest desc, intrest_defined desc', $m->id, $t->id );

    return undef unless $rec;

    $rec->{'member'} = $m;
    $rec->{'topic'} = $t;

    return $this->new( $rec );    
}

sub getset
{
    my( $this, $m, $t ) = @_;

    $m = Para::Member->get( $m );
    unless( ref $t )
    {
	$t = Para::Topic->find_one( $t );
    }

    warn "  getset interest $t->{id}\n";

    my $i = $this->get( $m, $t );
    unless( $i )
    {
	$this->create( $t, $m, 1);
	$i = $this->get( $m, $t );
    }
    return $i;
}

######## Methods

sub topic
{
    return shift->t(@_);
}

sub t
{
    my( $i ) = @_;

    unless( $i->{'topic'} )
    {
	$i->{'topic'} = Para::Topic->new( $i->{'intrest_topic'} );
    }
    return $i->{'topic'};
}

sub member
{
    return shift->m(@_);
}

sub m
{
    my( $i ) = @_;

    unless( $i->{'member'} )
    {
	$i->{'member'} = Para::Member->get( $i->{'intrest_member'} );
    }
    return $i->{'member'};
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
    return $_[0]->{'intrest_defined'} || 0;
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

sub update_by_query
{
    my( $i ) = @_;

    my $q = $Para::Frame::REQ->q;

    my $rec = {};

    foreach my $key (qw( belief knowledge theory skill experience
			 practice editor helper meeter bookmark
			 interest connected description defined ))
    {
	$rec->{$key} = $q->param( $key );
    }

    return $q->update( $rec );
}

sub update
{
    my( $i, $rec ) = @_;

    my @fields = ();
    my @values = ();

    $rec->{'defined'} || $rec->{'defined'} || 0;
    if( $rec->{'defined'} > $i->defined )
    {
	warn "  Changing interest_defined to $rec->{'defined'}\n";
	push @fields, 'intrest_defined';
	push @values, int $rec->{'defined'};
    }

    $rec->{'connected'} || 0;
    if( $rec->{'connected'} > $i->connected )
    {
	warn "  Changing interest_connected to $rec->{'connected'}\n";
	push @fields, 'intrest_connected';
	push @values, int $rec->{'connected'};
    }

    if( $rec->{'belief'} )
    {
	push @fields, 'intrest_belief';
	push @values, int $rec->{'belief'};
    }

    if( $rec->{'practice'} )
    {
	push @fields, 'intrest_practice';
	push @values, int $rec->{'practice'};
    }

    if( $rec->{'theory'} )
    {
	push @fields, 'intrest_theory';
	push @values, int $rec->{'theory'};
    }

    if( $rec->{'knowledge'} )
    {
	push @fields, 'intrest_knowledge';
	push @values, int $rec->{'knowledge'};
    }

    if( $rec->{'editor'} )
    {
	push @fields, 'intrest_editor';
	push @values, int $rec->{'editor'};
    }

    if( $rec->{'helper'} )
    {
	push @fields, 'intrest_helper';
	push @values, int $rec->{'helper'};
    }

    if( $rec->{'meeter'} )
    {
	push @fields, 'intrest_meeter';
	push @values, int $rec->{'meeter'};
    }

    if( $rec->{'bookmark'} )
    {
	push @fields, 'intrest_bookmark';
	push @values, int $rec->{'bookmark'};
    }

    if( $rec->{'interest'} )
    {
	push @fields, 'intrest';
	push @values, $rec->{'interest'};
    }

    if( $rec->{'description'} )
    {
	push @fields, 'description';
	push @values, $rec->{'description'};
    }

    # Nothing changed
    return 0 unless @values;

    # Update timestamp
    push @fields, 'intrest_updated';
    push @values, scalar(localtime);

    my $tid = $i->topic->id;
    my $mid = $i->member->id;

    my $statement = "update intrest set ".
	join( ', ', map("$_=?", @fields)) .
	"where intrest_topic=? and intrest_member=?";
    my $sth = $Para::dbh->prepare_cached( $statement );
    $sth->execute( @values, $tid, $mid ) or die;

    $i->member->score_change( 'intrest_stated', 1 );

    return 1;
}

sub next_step
{
    my( $in, $args ) = @_;

    # TODO: rewrite

    my $next = {};

    $next->{'handler'} = '/member/db/person/interest/specify.tt';
    $next->{'url'} = $next->{'handler'}."?tid=".$in->t->id;

    return $next;
}

###################  Class static methods

sub touch
{
    my( $this, $t, $m, $defined ) = @_;
    my $class = ref($this) || $this;
    $m ||= $Para::Frame::U;
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
    my $u = $Para::Frame::U;

    $m ||= $u;
    $t or throw('incomplete', "t missing\n");
    $defined ||= 1;

    my $mid = ref $m ? $m->id : $m;
    my $tid = ref $t ? $t->id : $t;

    if( $u->level < 40 and $u->id != $mid )
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
	    throw('create', "This interest already exists\n");
	}
	die;
    }

    return 1;
}

1;
