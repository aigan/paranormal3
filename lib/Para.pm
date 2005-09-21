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
use File::stat;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug );
use Para::Frame::Time qw( now duration );

use Para::Member;
use Para::Topic;
use Para::Widget;
use Para::Interest;
use Para::Interests::Tree;
use Para::Email;
use Para::Calendar;

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
    $Para::Topic::BATCHCOUNT ||= 1;
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


    # These are qick enough to be done directly
    #
    &timeout_login;
    &clear_tempfiles;


    $req->add_job('run_code', \&Para::Place::fix_zipcodes);

    $req->add_job('run_code', \&Para::Calendar::do_planned_actions);


    return unless $Para::SITE_CFG->{'do_bgjob'};

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

    my $recs = $Para::dbix->select_list("select member from member where latest_in is not null and (latest_out is null or latest_in > latest_out) order by latest_in");

    my $online = Para::Member->currently_online;
    my %seen = ();

    my $now = now();

    foreach my $rec ( @$recs, @$online )
    {
	my $m = Para::Member->get_by_id( $rec->{'member'} );
	next if $seen{$m->id} ++;

	my $latest_in = $m->latest_in;
	my $latest_seen = $m->latest_seen;

	# Failsafe in case no logout was registred
	if( $latest_in->delta_ms($now) > duration( hours => 40 ) )
	{
	    debug $m->desig." has been online since $latest_in";
	    $m->on_logout( $latest_in->add(hours=>1) );
	}
	elsif( $latest_seen->delta_ms($now) > duration( minutes => 30 ) )
	{
	    debug "Logging out ".$m->desig;
	    $m->on_logout( $now );
	}
    }
}


# This is for the old paranormal.se
#   Not needed for the paraframe version
#
sub clear_tempfiles
{
    opendir TMP, "/tmp" or die $!;
    while( my $file = readdir(TMP) )
    {
	next if $file eq "Psi_cache"; # not this file
	next unless $file =~ /^Psi_/;

	my $st = stat("/tmp/$file") or die $!;
	if( time - $st->ctime > 900 ) # 15 minutes old
	{
	    unlink "/tmp/$file" or die $!;
	}
    }
    close TMP;
}

1;
