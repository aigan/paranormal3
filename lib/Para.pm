#  $Id$  -*-perl-*-
package Para;

#=====================================================================
#
# DESCRIPTION
#   Paranormal.se overview class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2005 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;
use Data::Dumper;
use Time::Seconds qw( ONE_HOUR );

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug );
use Para::Frame::Time qw( now );

use Para::Member;
use Para::Topic;
use Para::Widget;
use Para::Interest;
use Para::Interests::Tree;
use Para::Email;

our $CLEAR_CACHE;

sub on_memory
{
    my( $size ) = @_;

    debug "Planning to clear some memory";

    my $topic_cache = scalar keys %{$Para::Topic::CACHE};
    my $member_cache = scalar keys %{$Para::Member::CACHE};
    my $arc_cache = scalar keys %Para::Arc::CACHE;
    my $alias_cache = scalar keys %Para::Alias::CACHE;
    my $place_cache = scalar keys %{$Para::Place::CACHE};
    my $template_cache = scalar keys %Para::Frame::Cache::td;

    debug "Topic cache  : $topic_cache";
    debug "Member cache : $member_cache";
    debug "Arc cache    : $arc_cache";
    debug "Alias cache  : $alias_cache";
    debug "Place cache  : $place_cache";
    debug "TT cache     : $template_cache";

    $CLEAR_CACHE = 1;
}

sub clear_caches
{
    # Called from busy_background_job
    my( $delta ) = @_;

    if( $CLEAR_CACHE )
    {
	debug "Clearing caches";

	foreach my $tkey ( keys %{$Para::Topic::CACHE} )
	{
	    my $t = $Para::Topic::CACHE->{$tkey};
	    next unless $t;
#	    warn "Clearing $tkey fore removal\n";
	    $t->clear_cached;
	}
	$Para::Topic::CACHE = {};

	foreach my $arc ( values %Para::Arc::CACHE )
	{
#	    warn "Clearing $arc->{rel_topic} for removal\n";
	    $arc->clear_cached;
	}
	%Para::Arc::CACHE = ();

	foreach my $m ( values %{$Para::Member::CACHE} )
	{
#	    warn "Clearing $m->{member} for removal\n";
	    $m->clear_cached;
	}
	$Para::Member::CACHE = {};

	%Para::Alias::CACHE = ();

	$CLEAR_CACHE = 0;
    }
}

sub add_background_jobs
{
    my( $delta, $sysload ) = @_;
    my( $req ) = $Para::Frame::REQ;

    my $added = 0;

    # Just to avoid insanely large nymbers
    if( $Para::Topic::BATCHCOUNT > 1000000 )
    {
	$Para::Topic::BATCHCOUNT = 1;
    }

    foreach my $t ( values %$Para::Topic::TO_PUBLISH_NOW,
		    values %$Para::Topic::TO_PUBLISH )
    {
	$req->add_job('run_code', sub
		      {
			  $t->publish;
		      });
	$added ++;
    }

    $req->add_job('run_code', \&timeout_login);
    $req->add_job('run_code', \&Para::Place::fix_zipcodes);
    

    return unless $Para::Frame::CFG->{'do_bgjob'};

    eval
    {
	unless( $added )
	{
	    $added += Para::Topic->publish_from_queue();
	}
	
	unless( $added )
	{
	    $added += Para::Topic->vacuum_from_queue(1);
	}
    };
    if( $@ )
    {
	debug "ERROR while setting up jobs:";
	debug $@;
    }
    else
    {
	debug "Finished setting up background jobs";
    }
    return 1;
}

sub timeout_login
{
    my( $req ) = @_;

    my $recs = $Para::dbix->select_list("select member  from member where latest_in is not null and (latest_out is null or latest_in > latest_out) order by latest_in");

    my $now = now();

    foreach my $rec ( @$recs )
    {
	my $m = Para::Member->get_by_id( $rec->{'member'} );

	my $latest_in = $m->latest_in;
	my $latest_seen = $m->latest_seen;

	# Failsafe in case no logout was registred
	if( $latest_in < $now - 40 * ONE_HOUR )
	{
	    debug $m->desig." has been online since $latest_in";
	    $m->latest_out( $latest_in + ONE_HOUR );
	}
	elsif( $latest_seen < $now - 30 * 60 )
	{
	    debug "Logging out ".$m->desig;

	    # Temporary disabled...
#	    $m->latest_out( $now );
	}
    }
}


####### Cleanup we may want to do...
###
####### DAILY cleenup
###
###    ### Remove disable aliases for inactive topics
###    #
###    $Psi::dbh->do("update talias set talias_status=0, talias_active='f' where talias_active is true and talias_t not in (select t from t where t=talias_t and t_active is true)");
###    
###    ### Remove empty aliases
###    #
###    $Psi::dbh->do("delete from talias where talias=''");
###
###
####### Houerly cleenup
###
###    ### Remove rels pointing to/from inactive topics
###    #
###    warn "Remove rels pointing to/from inactive topics\n" if $DEBUG;
###    my $st  = qq{
###	update rel set rel_status=0, rel_active='f', rel_updated=now(), rel_changedby = -1 where
###	    (not exists ( select 1 from t where t=rev))
###	    or
###	    (rel is not null and not exists ( select 1 from t where t=rel))
###	    or
###	    (rel_status > 1 and not exists ( select 1 from t where t=rev and t_active is true))
###	    or
###	    (rel is not null and rel_status > 1 and not exists ( select 1 from t where t=rel and t_active is true))
###	};
###    my $sth = $Psi::dbh->prepare($st);
###    $sth->execute;
###
###
###    ### Move lost entries to Lost entry
###    warn "Move lost entries to Lost entry\n" if $DEBUG;
###    my $st3 = "update t set t_entry_parent = 137624 where t_active and t in (select t from t as y where t_active and t_entry and t_entry_parent is null and not exists (select t from t where t_active is true and t_entry_next = y.t))";
###    my $sth3 = $Psi::dbh->prepare($st3);
###    $sth3->execute;
###

1;
