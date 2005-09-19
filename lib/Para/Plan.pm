#  $Id$  -*-perl-*-
package Para::Plan;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se Plan class
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

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( throw debug );
use Para::Frame::Time qw( now );
use Para::Frame::DBIx qw( pgbool );

use Para::Event;

our %FIELDMAP =
    (
     start       => 'plan_start',
     end         => 'plan_end',
     event       => 'plan_event',
     is_action   => 'plan_is_action',
     id          => 'plan_id',
     );

our %FIELDTYPE =
    (
     plan_start => 'date',
     plan_end => 'date',
     plan_is_action => 'boolean',
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

    my $rec = $Para::dbix->select_record("from plan where plan_id=?", $id);
    return $this->new($rec);
}

sub add
{
    my( $this, $rec ) = @_;

    my $id = $Para::dbix->get_nextval('plan_seq');
    $rec->{'plan_id'} = $id;

    return $this->get_by_id(
			    $Para::dbix->insert_wrapper({
				rec => $rec,
				map => \%FIELDMAP,
				types => \%FIELDTYPE,
				table => 'plan',
				unless_exists => ['start', 'event'],
				return_field => 'id',
			    }));
}

sub event
{
    unless( ref $_[0]->{'plan_event'} )
    {
	return $_[0]->{'plan_event'} =
	    Para::Event->get_by_id( $_[0]->{'plan_event'} );
    }
    return $_[0]->{'plan_event'};
}

sub do_all
{
    return $_[0]->event->do_all;
}

sub action
{
    return $_[0]->event->action;
}

sub as_user
{
    return $_[0]->event->as_user;
}

sub id
{
    return $_[0]->{'plan_id'};
}

sub start
{
    unless( ref $_[0]->{'plan_start'} )
    {
	return $_[0]->{'plan_start'} = date( $_[0]->{'plan_start'} );
    }
    return $_[0]->{'plan_start'};
}

sub started
{
    return undef unless $_[0]->{'plan_started'} ;
    unless( ref $_[0]->{'plan_started'} )
    {
	return $_[0]->{'plan_started'} = date( $_[0]->{'plan_started'} );
    }
    return $_[0]->{'plan_started'};
}

sub end
{
    return undef unless $_[0]->{'plan_end'} ;
    unless( ref $_[0]->{'plan_end'} )
    {
	return $_[0]->{'plan_end'} = date( $_[0]->{'plan_end'} );
    }
    return $_[0]->{'plan_end'};
}

sub ended
{
    return undef unless $_[0]->{'plan_ended'} ;
    unless( ref $_[0]->{'plan_ended'} )
    {
	return $_[0]->{'plan_ended'} = date( $_[0]->{'plan_ended'} );
    }
    return $_[0]->{'plan_ended'};
}

sub finished
{
    return $_[0]->{'plan_finished'} ? 1 : 0;
}

sub is_action
{
    return $_[0]->{'plan_is_action'} ? 1 : 0;
}

sub execute_as_job
{
    my( $plan ) = @_;

    my $req = $Para::Frame::REQ;
    $req->add_job('run_code', sub {
	$plan->execute(@_);
    });
}

sub execute
{
    my( $plan, $req ) = @_;

    $req ||= $Para::Frame::REQ;
    my $action = $plan->action;
    my $as_user= $plan->as_user || $Para::Frame::U;

    my $current_user = $Para::Frame::U;
    Para::Member->change_current_user( $as_user );
    $plan->set_started;
    if( $req->run_action( $plan->action, $plan ) )
    {
	$plan->set_finished;
	debug "Finished action $action";
	$Para::dbix->commit;
    }
    else
    {
	debug "Execution of planned event action $action failed";
	debug(1);
	foreach my $part (@{ $req->result->parts })
	{
	    my $type = $part->{'type'} || '';
	    my $msg  = $part->{'message'};
	    debug "$type:\n$msg\n";
	    if( $part->{'view_context'} )
	    {
		my $line = $part->{'context_line'};
		my $context = $part->{'context'};
		if( length $context )
		{
		    debug "Context at line $line:\n";
		    debug $context;
		}
	    }
	}
	debug(-1);
	$plan->{'plan_started'} = undef;
	$Para::dbix->update('plan',
			    {plan_started=>undef},
			    {plan_id=>$plan->id},
			    );
    }
    Para::Member->change_current_user( $current_user );
}

sub do_not_execute
{
    my( $plan ) = @_;
    $plan->set_finished;
}

sub set_started
{
    my( $plan, $started ) = @_;

    my $pid = $plan->id;

    $started ||= now();
    $plan->{'plan_started'} = $started;
    $Para::dbix->update('plan',
			{plan_started=>$started},
			{plan_id=>$plan->id},
			);
    
}

sub set_finished
{
    my( $plan, $ended ) = @_;

    # Set the ended time IF we startd. A setting of finished whithout
    # started will indicate that we didn't need to run this action and
    # just marked it done anyway

    $ended ||= now();

    $plan->{'plan_finished'} = 1;

    my $params =
    {
	plan_finished => pgbool(1),
    };

    if( $plan->started )
    {
	$plan->{'plan_ended'} =
	    $params->{'plan_ended'} = $ended;
    }

    $Para::dbix->update('plan', $params,
			{plan_id=>$plan->id},
			);
    return 1;
}

1;

