#  $Id$  -*-perl-*-
package Para::TS;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se arcs list class
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

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug maxof );
use Para::Frame::DBIx qw( pgbool );

use Para::Topic;
use Para::Constants qw( S_REPLACED );

#
# "entry" is a media that says something about "topic" 
#

### Constructors

sub new
{
    my( $this, $rec ) = @_;
    my $class = ref($this) || $this;

    unless( ref $rec eq 'HASH' )
    {
	die "Not implemented";
    }

    if( $rec )
    {
	return bless($rec, $class);
    }
    else
    {
	return undef;
    }
}

sub get
{
    my( $this, $eid, $tid ) = @_;

    $eid = $eid->id if ref $eid;
    $tid = $tid->id if ref $tid;

    my $rec = $Para::dbix->select_possible_record("from ts where ts_entry=? and ts_topic=?", $eid, $tid);

    return undef unless $rec;
    return $this->new( $rec );
}

=head2 rel_list

  Para::TS->rel_list( $tid )

Returns listref of the topics that $tid says something about

=cut

sub rel_list
{
    my( $this, $tid, $crits ) = @_;

    $tid = $tid->id if ref $tid;
    $crits ||= {};

    my $recs;
    if( $crits->{'include_inactive'} )
    {
	$recs = $Para::dbix->select_list("from ts where ts_entry=?", $tid);
    }
    else
    {
	$recs = $Para::dbix->select_list("from ts where ts_entry=? and ts_active is true", $tid);
    }

    my @tss;

    foreach my $rec ( @$recs )
    {
	push @tss, Para::TS->new( $rec );
    }
    return \@tss;
}

=head2 rev_list

  Para::TS->rev_list( $tid )

Returns listref of media topics that says something about $tid

=cut

sub rev_list
{
    my( $this, $tid, $crits ) = @_;

    $tid = $tid->id if ref $tid;
    $crits ||= {};

    my $recs;
    if( $crits->{'include_inactive'} )
    {
	$recs = $Para::dbix->select_list("from ts where ts_topic=?", $tid);
    }
    else
    {
	$recs = $Para::dbix->select_list("from ts where ts_topic=? and ts_active is true", $tid);
    }

    my @tss;

    foreach my $rec ( @$recs )
    {
	push @tss, Para::TS->new( $rec );
    }
    return \@tss;
}

sub set
{
    my( $this, $e, $t, $active ) = @_;

    $e = Para::Topic->get_by_id( $e ) unless ref $e;
    $t = Para::Topic->get_by_id( $t ) unless ref $t;
    $active = 1 unless defined $active;

    my $eid = $e->id;
    my $tid = $t->id;

    debug("eid $eid, tid $tid, active $active");

    my $ts = $this->get( $eid, $tid );

    my $m = $Para::Frame::U;
    my $mid = $m->id;
    my $dbh = $Para::dbh;

    my $new_status;
    if( $ts )
    {
	$new_status = maxof( $m->new_status, $ts->status );
    }
    else
    {
	$new_status = $m->new_status;
    }
    if( not $active )
    {
	$new_status = S_REPLACED;
    }

    my $change = 0;

    if( $ts )
    {
	if( $active xor $ts->active )
	{
	    if( $m->status >= $ts->status )
	    {
		my $st_u = "update ts set ts_active=?, ts_status=?, ts_updated=now(), ".
		    "ts_changedby=? where ts_entry=? and ts_topic=?";
		my $sth_u = $dbh->prepare_cached( $st_u );
		$sth_u->execute( pgbool($active), $new_status, $mid, $eid, $tid );
		$change ++;
	    }
	}
    }
    else
    {
	if( $active )
	{
	    my $st_add = "insert into ts ( ts_entry, ts_topic, ts_createdby, ts_changedby, ".
		"ts_status, ts_active ) values ( ?, ?, ?, ?, ?, ? )";
	    warn "$st_add ($eid, $tid, $mid, $mid, $new_status, $active)\n";
	    my $sth_add = $dbh->prepare_cached( $st_add );
	    $sth_add->execute($eid, $tid, $mid, $mid, $new_status, pgbool($active));
	    $change ++;
	}
    }

    Para::Topic->get_by_id( $tid )->mark_publish;
    Para::Topic->get_by_id( $eid )->mark_publish;

    return $change;
}

### Methods

sub topic
{
    Para::Topic->get_by_id( shift->{'ts_topic'} );
}

sub entry
{
    Para::Topic->get_by_id( shift->{'ts_entry'} );
}

sub comment { shift->{'ts_comment'} };

sub status
{
    return $_[0]->{'ts_status'};
}

sub active
{
    return $_[0]->{'ts_active'} ? 1: 0;
}

1;
