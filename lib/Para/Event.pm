#  $Id$  -*-perl-*-
package Para::Event;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se Event class
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

use DateTime::Event::Cron;
use DateTime::Format::ICal;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug trim );
use Para::Frame::Time qw( now date );

use Para::Member;
use Para::Plan;

our %FIELDMAP =
    (
     topic     => 'event_topic',
     rule_type => 'event_rule_type',
     rule      => 'event_rule',
     action    => 'event_action',
     do_all    => 'event_do_all',
     as_user   => 'event_as_user',
     );

our %FIELDTYPE =
    (
     event_do_all => 'boolean',
     event_created => 'date',
     event_updated => 'date',
     );

our %FIELDPARSER =
    (
     event_as_user => sub{ Para::Member->get_by_nickname(shift) },
     event_topic   => sub{ Para::Topic->find_one(shift) },
     );

sub new
{
    my( $this, $rec ) = @_;
    my $class = ref($this) || $this;
    return bless( $rec, $class );
}

sub get_by_id
{
    my( $this, $id ) = @_;

    my( $rec ) = $Para::dbix->select_record("from event where event_id=?", $id);
    if( $rec )
    {
	return $this->new($rec);
    }
    else
    {
	return undef;
    }
}

sub list
{
    my( $this, @args ) = @_;

    my $recs = $Para::dbix->select_list("from event order by event_id");
    my @events;
    foreach my $rec ( @$recs )
    {
	push @events, $this->new( $rec );
    }
    return \@events;
}

sub create
{
    my( $this, $rec ) = @_;

    my $eid = $Para::dbix->get_nextval('event_seq');
    $rec->{'event_id'} = $eid;
    $Para::dbix->insert_wrapper({
	rec => $rec,
	map => \%FIELDMAP,
	parser => \%FIELDPARSER,
	types => \%FIELDTYPE,
	table => 'event',
    });

    return $this->get_by_id( $eid );
}

sub add_to_plan
{
    my( $e, $span_or_date ) = @_;

    if( $span_or_date->isa('DateTime::Span') )
    {
	return $e->add_span_to_plan( $span_or_date );
    }
    else
    {
	return $e->add_date_to_plan( $span_or_date );
    }
}

sub add_span_to_plan
{
    my( $e, $span ) = @_;

    unless( $e->has_sensible_intervals )
    {
	my $eid = $e->id;
	die "Event $eid takes place to often:\n";
    }

    debug "Checking events during $span";
    my $iter = $e->dts->iterator( span => $span );

    my $cnt=0;
    while()
    {
	my $dt = $iter->next;
	last if not $dt;
	$e->add_date_to_plan( $dt );
	last if ++ $cnt >= 200;
    }
}

sub add_date_to_plan
{
    my( $e, $start ) = @_;

    my( $end );

    debug "Adding a plan for event at $start";

    if( $e->duration )
    {
	$end = $start + $e->duration;
    }

    return Para::Plan->add({
	start => $start,
	end   => $end,
	event => $e,
	is_action => $e->is_action,
    });
}

sub has_sensible_intervals
{
    my( $e ) = @_;

    my $interval = $e->sample_interval;
    if( $interval < DateTime::Duration->new( minutes => 30 ) )
    {
	my $eid = $e->id;
	my $minutes = $interval->delta_minutes;
	debug "Event $eid has an interval of $minutes minutes";
	return 0;
    }
    else
    {
	return 1;
    }
}

sub sample_interval
{
    my( $e ) = @_;

    unless( exists $e->{'sample_interval'} )
    {
	my $dts = $e->dts;
	my $now = now();
	my $first = $dts->next( $now );
	debug 4, "First is $first";
	my $second = $dts->next( $first );
	debug 4, "Second is $second";

	$e->{'sample_interval'} = $second - $first;
    }
    return $e->{'sample_interval'};
}

sub dts # DateTime Set
{
    my( $e ) = @_;

    unless( $e->{'dts'} )
    {
	$e->parse_rule;
    }

    return $e->{'dts'};
}

sub duration
{
    my( $e ) = @_;

    unless( exists $e->{'duration'} )
    {
	$e->parse_rule;
    }

    return $e->{'duration'};
}

sub rule_type
{
    return $_[0]->{'event_rule_type'};
}

sub rule
{
    return $_[0]->{'event_rule'};
}

sub id
{
    return $_[0]->{'event_id'};
}

sub is_action
{
    return length( $_[0]->{'event_action'} ) ? 1 : 0;
}

sub do_all
{
    return $_[0]->{'event_do_all'} ? 1 : 0;
}

sub active
{
    return $_[0]->{'event_active'} ? 1 : 0;
}

sub action
{
    return $_[0]->{'event_action'};
}

sub as_user
{
    return undef unless $_[0]->{'event_as_user'};
    unless( ref $_[0]->{'event_as_user'} )
    {
	return $_[0]->{'event_as_user'} =
	    Para::Member->get_by_id( $_[0]->{'event_as_user'} );
    }
    return $_[0]->{'event_as_user'};
}

sub created_by
{
    unless( ref $_[0]->{'event_createdby'} )
    {
	return $_[0]->{'event_createdby'} =
	    Para::Member->get( shift->{'event_createdby'});
    }
    return $_[0]->{'event_createdby'};
}

sub created
{
    unless( ref $_[0]->{'event_created'} )
    {
	return $_[0]->{'event_created'} =
	    date( $_[0]->{'event_created'} );
    }
    return $_[0]->{'event_created'};
}

sub updated_by
{
    return undef unless $_[0]->{'event_updatedby'};
    unless( ref $_[0]->{'event_updatedby'} )
    {
	return $_[0]->{'event_updatedby'} =
	    Para::Member->get( shift->{'event_updatedby'});
    }
    return $_[0]->{'event_updatedby'};
}

sub updated
{
    unless( ref $_[0]->{'event_updated'} )
    {
	return $_[0]->{'event_updated'} =
	    date( $_[0]->{'event_updated'} );
    }
    return $_[0]->{'event_updated'};
}

sub topic
{
    return undef unless $_[0]->{'event_topic'};
    unless( ref $_[0]->{'event_topic'} )
    {
	return $_[0]->{'event_topic'}
	= Para::Topic->get_by_id( $_[0]->{'event_topic'} );
    }
    return $_[0]->{'event_topic'};
}

sub parse_rule
{
    my( $e ) = @_;

    my $rule_type = $e->rule_type;

    my( $dts, $dur ); # DateTime Set and DateTime Duration
    if( $rule_type eq 'cron' )
    {
	$e->parse_rule_as_cron;
    }
    elsif( $rule_type eq 'ical' )
    {
	$e->parse_rule_as_ical;
    }
    else
    {
	die "rule_type $rule_type not recognized";
    }

    return 1;
}

sub parse_rule_as_cron
{
    my( $e ) = @_;

    my $dts = DateTime::Event::Cron->from_cron($e->rule);

    $e->{'dts'} = $dts;
    $e->{'duration'} = undef;
    return 1;
}


sub parse_rule_as_ical
{
    my( $e ) = @_;

    my @rows = split /\n\r?/, $e->rule;
    my( $dts, $dur );

    foreach my $row ( @rows )
    {
	trim(\$row);
	next unless length $row;
	if( $row =~ /^[^=]+:/ )
	{
	    my( $tag, $val ) = split /\s+:\s+/, $row;
	    if( $tag eq 'RECUR' )
	    {
		$dts = DateTime::Format::ICal->parse_recurrence( recurrence => $val );
	    }
	    elsif( $tag eq 'DURATION' )
	    {
		my $dur = DateTime::Format::ICal->parse_duration( $val );
	    }
	}
	else
	{
	    $dts = DateTime::Format::ICal->parse_recurrence( recurrence => $row );
	}
    }

    $e->{'dts'} = $dts;
    $e->{'duration'} = $dur;
}

sub update
{
    my( $e, $rec ) = @_;
    return $Para::dbix->update_wrapper({
	rec => $rec,
	rec_old => $e->get_by_id( $e->id ),
	map => \%FIELDMAP,
	parser => \%FIELDPARSER,
	types => \%FIELDTYPE,
	table => 'event',
	key =>
	{
	    'event_id' => $e->id,
	},
	on_update =>
	{
	    event_updated => now(),
	    event_updatedby => $Para::Frame::U->id,
	}
    });
}

1;

