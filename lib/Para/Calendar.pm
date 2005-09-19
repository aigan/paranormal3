#  $Id$  -*-perl-*-
package Para::Calendar;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se Calendar class
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
use DateTime::Span;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug trim );
use Para::Frame::Time qw( date now duration );

use Para::Event;
use Para::Plan;

our $LAST_RUN;

### Functions

sub do_planned_actions
{
    my( $req ) = @_;
    my $c = "Para::Calendar";

    my $last_run = $c->last_run;
    my $now = now();

    my $span = DateTime::Span->from_datetimes( after => $last_run,
					       end => $now );

    $c->add_events_to_plan( $span );

    $c->do_action_events($now);
    $LAST_RUN = $now;
}

### Methods

sub do_action_events
{
    my( $c, $til ) = @_;

    # 1. Do the do_all events
    # 2. Do the do_latest events (backwards)
    # 3. Do the rest of the events

    my $recs = $Para::dbix->select_list("from plan where plan_finished is false and plan_is_action is true and plan_start <= ? and plan_started is null", $til);

    my %plan_one;
    foreach my $rec ( @$recs )
    {
	my $plan = Para::Plan->new( $rec );
	if( $plan->do_all )
	{
	    $plan->execute;
	}
	else
	{
	    $plan_one{ $plan->event->id } ||= [];
	    push @{ $plan_one{ $plan->event->id } }, $plan;
	}
    }

    foreach my $plan_list ( values %plan_one )
    {
	my $one_plan = pop @$plan_list;
	$one_plan->execute_as_job;

	foreach my $plan (@$plan_list )
	{
	    $plan->do_not_execute;
	}
    }
}

sub add_events_to_plan
{
    my( $c, $span ) = @_;

    my $recs = $Para::dbix->select_list("from event where event_active is true");
    foreach my $rec ( @$recs )
    {
	my $event = Para::Event->new( $rec );
	$event->add_to_plan( $span );
    }
}

sub last_run
{
    my( $c ) = @_;

    unless( $LAST_RUN )
    {
	my $rec = $Para::dbix->select_possible_record("select plan_start from plan where plan_finished is true order by plan_start desc limit 1");
	if( $rec )
	{
	    $LAST_RUN = date( $rec->{'plan_start'} );
	}
	else
	{
	    $LAST_RUN = now() - duration(days=>1);
	}
	debug "Initiating LAST_RUN to $LAST_RUN";
    }

    return $LAST_RUN;
}

1;

__END__
