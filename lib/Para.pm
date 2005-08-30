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

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::Utils qw( debug );

use Para::Member;
use Para::Topic;
use Para::Widget;
use Para::Interest;
use Para::Interests::Tree;
use Para::Email;

sub on_memory
{
    my( $size ) = @_;

    debug "Should clear some memory";

    my $topic_cache = scalar keys %{$Para::Topic::CACHE};
    my $member_cache = scalar keys %{$Para::Member::CACHE};
    my $arc_cache = scalar keys %Para::Arc::CACHE;
    my $alias_cache = scalar keys %Para::Alias::CACHE;

    debug "Topic cache  : $topic_cache";
    debug "Member cache : $member_cache";
    debug "Arc cache    : $arc_cache";
    debug "Alias cache  : $alias_cache";

    $Para::Topic::CACHE = {};
    $Para::Member::CACHE = {};
    %Para::Arc::CACHE = ();
    %Para::Alias::CACHE = ();
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

    foreach my $t ( values %$Para::Topic::to_publish_now,
		    values %$Para::Topic::to_publish )
    {
	$req->add_job('run_code', sub
		      {
			  $t->publish;
		      });
	$added ++;
    }
    
    $Para::Topic::to_publish     = {};
    $Para::Topic::to_publish_now = {};

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

1;
