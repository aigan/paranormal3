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
use Carp qw( cluck confess );
use locale;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( trim throw uri datadump );
use Para::Frame::Time qw( date now );

use Para::Arcs;
use Para::Member;
use Para::Topic;

our %FIELDMAP =
    (
     belief      => 'belief',
     knowledge   => 'knowledge',
     theory      => 'theory',
     skill       => 'skill',
     experience  => 'experience',
     practice    => 'practice',
     editor      => 'editor',
     helper      => 'helper',
     meeter      => 'meeter',
     bookmark    => 'bookmark',
     interest    => 'intrest',
     connected   => 'intrest_connected',
     description => 'intrest_description',
     defined     => 'intrest_defined',
     updated     => 'intrest_updated',
     );

our %FIELDTYPE =
    (
     intrest_updated     => 'date',

     intrest_member      => 'integer',
     intrest_topic       => 'integer',
     belief              => 'integer',
     knowledge           => 'integer',
     theory              => 'integer',
     skill               => 'integer',
     practice            => 'integer',
     editor              => 'integer',
     helper              => 'integer',
     meeter              => 'integer',
     bookmark            => 'integer',
     visit_latest        => 'date',
     visit_version       => 'integer',
     intrest_updated     => 'date',
     experience          => 'integer',
     intrest_description => 'string',
     intrest_defined     => 'integer',
     intrest_connected   => 'integer',
     intrest             => 'integer',
     );

######## Constructor

=head2 _new

  Para::Interest->_new( $rec )

Create object. The caller must take care of the cache and use the
cahce before calling this!

=cut

sub _new
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
    my( $this, $m, $t, $rec, $nocache ) = @_;

    unless( ref $m )
    {
	$m = Para::Member->get( $m );
    }

    unless( ref $t )
    {
	$t = Para::Topic->get_by_id( $t );
    }

    my $ins_db = $m->interests->{'db'};
    my $tid = $t->id;

    if( not $ins_db->{$tid} or $nocache )
    {
	warn "  get interest $tid\n";

	$rec ||= $Para::dbix->select_possible_record('from intrest where intrest_member=? and intrest_topic=? order by intrest desc, intrest_defined desc', $m->id, $tid );

	return undef unless $rec;
	warn "    found\n";

	$rec->{'member'} = $m;
	$rec->{'topic'} = $t;

	return $this->_new( $rec ) if $nocache;

	$ins_db->{$tid} = $this->_new( $rec );
    }

    return $ins_db->{$tid};
}

sub getset
{
    my( $this, $m, $t, $rec, $nocache ) = @_;

    unless( ref $m )
    {
	$m = Para::Member->get( $m );
    }

    unless( ref $t )
    {
	$t = Para::Topic->get_by_id( $t );
    }

#    warn "  getset interest ".$t->id."\n";

    my $i = $this->get( $m, $t, $rec, $nocache );

    $i ||= $this->create( $m, $t, 1);

    $i or die "Failed to create interest".$t->id;

    return $i;
}


###################  Class static methods

sub touch
{
    die "deprecated";

    my( $this, $m, $t, $defined ) = @_;
    my $class = ref($this) || $this;
    $m ||= $Para::Frame::U;
    $t or throw('incomplete', "t missing\n");
    $defined ||= 1;

    my $mid = ref $m ? $m->id : $m;
    my $tid = ref $t ? $t->id : $t;

    my $st_find = "select * from intrest where intrest_topic=? and intrest_member=?";
    my $sth_find = $Para::dbh->prepare( $st_find );
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
    my( $this, $m, $t, $defined ) = @_;
    my $class = ref($this) || $this;
    my $u = $Para::Frame::U;

    $m ||= $u;
    $t or throw('incomplete', "t missing\n");
    $defined ||= 1;

    my $mid = ref $m ? $m->id : $m;
    my $tid = ref $t ? $t->id : $t;

    $mid or confess "No member given";
    $tid or confess "No topic given: ".datadump($t,2);

    if( $u->level < 40 and $u->id != $mid )
    {
	throw('denied', "Du har inte access för att ändra någon annans intressen.");
    }


    warn "  create interest ".$t->id."\n";

    my $sth = $Para::dbh->prepare("insert into intrest
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

    warn "    success\n";


    my $i = $this->get( $m, $t );

    # Reset cache
    #
    $m->interests->add_to_list($i);

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
	$i->{'topic'} = Para::Topic->get_by_id( $i->{'intrest_topic'} );
    }
    return $i->{'topic'};
}

sub tid
{
    return $_[0]->{'intrest_topic'};
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

sub mid
{
    return $_[0]->{'intrest_member'};
}

sub general
{
    return $_[0]->{'intrest'};
}

sub comment
{
    return $_[0]->{'intrest_description'};
}

sub belief
{
    return $_[0]->{'belief'} || 0;
}

sub knowledge
{
    return $_[0]->{'knowledge'} || 0;
}

sub theory
{
    return $_[0]->{'theory'} || 0;
}

sub skill
{
    return $_[0]->{'skill'} || 0;
}

sub practice
{
    return $_[0]->{'practice'} || 0;
}

sub editor
{
    return $_[0]->{'editor'} || 0;
}

sub helper
{
    return $_[0]->{'helper'} || 0;
}

sub meeter
{
    return $_[0]->{'meeter'} || 0;
}

sub bookmark
{
    return $_[0]->{'bookmark'} || 0;
}

sub experience
{
    return $_[0]->{'experience'} || 0;
}

sub visit_latest
{
    unless( ref $_[0]->{'visit_latest'} )
    {
	$_[0]->{'visit_latest'} = date( $_[0]->{'visit_latest'} );
    }
    return $_[0]->{'visit_latest'};
}

sub visit_version
{
    return $_[0]->{'visit_version'} || undef;
}

sub updated
{
    unless( ref $_[0]->{'intrest_updated'} )
    {
	$_[0]->{'intrest_updated'} = date( $_[0]->{'intrest_updated'} );
    }
    return $_[0]->{'intrest_updated'};
}

sub description
{
    return $_[0]->{'intrest_description'} || "";
}

sub defined
{
    return $_[0]->{'intrest_defined'} || 0;
}

sub connected
{
    return $_[0]->{'intrest_connected'} || 0;
}

sub interest
{
    return $_[0]->{'intrest'} || 0;
}

###########

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
    my( $intr ) = @_;

    return( sprintf "%s intresse för %s ligger på %d%%",
	    $intr->member->desig,
	    $intr->topic->desig,
	    $intr->interest,
	    );

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
	my $val = $q->param( $key );
	next unless defined $val;
	$rec->{$key} = $val;
    }

    return $i->update( $rec );
}

sub update
{
    my( $i, $rec ) = @_;

    my $m = $i->m;

    $rec->{'defined'} ||= 0; # TODO: Allow lowering the value
    if( $rec->{'defined'} > $i->defined )
    {
	warn "  Changing interest_defined to $rec->{'defined'}\n";
	$rec->{'intrest_defined'} = int $rec->{'defined'};
    }

    $rec->{'connected'} ||= 0; # TODO: Allow lowering the value
    if( $rec->{'connected'} > $i->connected )
    {
	warn "  Changing interest_connected to $rec->{'connected'}\n";
	$rec->{'intrest_connected'} = int $rec->{'connected'};
    }

    my $tid = $i->topic->id;
    my $mid = $m->id;

    my $changes = $Para::dbix->update_wrapper({
	rec => $rec,
	rec_old => $i->getset( $m, $i->t, undef, 1 ),
	types => \%FIELDTYPE,
	table => 'intrest',
	key =>
	{
	    intrest_topic => $tid,
	    intrest_member => $mid,
	},
	on_update =>
	{
	    intrest_updated => now(),
	},
	fields_to_check => [values %FIELDMAP],
	map => \%FIELDMAP,
	copy_data => $i,
    });
					      
    # Nothing changed?
    return 0 unless $changes;

    $m->score_change( 'intrest_stated', 1 );

    # Update cache
    #
    $m->interests->change_in_list( $i );

    return $changes;
}

sub next_step
{
    my( $in, $args ) = @_;

    $args ||= {};

    my $defined = $args->{'defined'} || 0;
    my $redefine = $args->{'redefine'} || 0;
    my $interest = $in->interest || 0;

    # 1. Define relations 1-10
    # 2. Specify intrest
    # 3. Define relations 11-20
    # 4. Specify related intrests
    # 5. Define relations 21-50

    my $base = "/member/db/person/interest";

    my $tmpl;
    
    if( $defined < 30 or $redefine )
    {
	$tmpl = $base.'/specify.tt';
    }
    elsif( $defined < 90 and ( not $interest or $interest > 30 ) )
    {
	$tmpl = $base.'/specify_related.tt';
    }
    else
    {
	$tmpl = $base.'/specify_list.tt';
    }

    my $next = {};

    $next->{'template'} = $tmpl;
    $next->{'url'} = uri( $tmpl, {tid => $in->t->id} );

    return $next;
}

1;
