#  $Id$  -*-perl-*-
package Para::Interests;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se Member interests list
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
use Carp;
use locale;
use Date::Manip;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    warn "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Frame::DBIx;
use Para::Frame::Utils qw( throw debug );

use Para::Interest;
use Para::Constants qw( :all );

###################  Class static methods

sub new
{
    my( $this, $member ) = @_;
    my $class = ref($this) || $this;

    my $ins = {};
    $ins->{'member'} = $member;
    $ins->{'list'} = undef;
    $ins->{'init'} = 0;
    $ins->{'db'} = {};

    return bless $ins, $class;
}

sub init_list
{
    my( $ins ) = @_;
    return if $ins->{'list'};
    # Put the most interesting topic first in the list
    $ins->{'list'} = $Para::dbix->select_list('from intrest where intrest_member=? and intrest is not null order by intrest desc',
				   $ins->m->id );
    return;
}

sub count
{
    my( $ins ) = @_;
    $ins->init_list unless $ins->{'list'};
    return scalar @{ shift->{'list'} };
}

sub updated
{
    my( $ins ) = @_;
    return Para::Time->get( $ins->member->{'intrest_updated'} );
}


sub member { shift->{'member'} }

sub summary
{
    my( $ins, $max, $cutof ) = @_;

    debug(1,"Creating a summary");

    $max   ||= 10;
    $cutof ||= 95;
    my $definedness_limit = 25;
    my $min = int( $max / 2 );
    my $step = 10;
    my $done = 0;
    my $i = 0;
    my $sum_cnt = 0;
    my $sum_idx = {};
    my $replaced = {};

    for($i=0; 1; $i++)
    {
	my $in = $ins->list_item( $i ) or last;
	my $topic = $in->topic;

	last if $in->general < TRUE_MIN;
	next unless $topic->active;
	next if $in->defined < $definedness_limit;

	debug(1,"Consider ".$topic->desig);


	if( $in->general < $cutof )
	{
	    if( $sum_cnt < $min )
	    {
		$cutof -= $step;
	    }
	    else
	    {
		last;
	    }
	}

	if( $sum_cnt < $max )
	{
	    $sum_idx->{ $topic->id } = $in;
	    $sum_cnt = scalar keys %$sum_idx;
	    debug(1,"  added");
	}

	if( $sum_cnt > 1 )
	{
	    # Collapse list

	    # 1. is this or other sub or super?  Keep super

	    debug(1);
	    foreach my $ointr ( values %$sum_idx, values %$replaced )
	    {
		next if $ointr->equals( $in );

		if( $topic->has_rel([1,2,3,4], $ointr->topic) )
		{
		    debug(1,"under ".$ointr->topic->desig);

		    delete $sum_idx->{ $topic->id };
		    $sum_cnt = scalar keys %$sum_idx;
		    last;
		}
		elsif( $ointr->topic->has_rel([1,2,3,4], $topic) )
		{
		    debug(1,"over ".$ointr->topic->desig);

		    # Keep if REALY intrested or comment given
		    unless( $ointr->general >= 98 or $ointr->comment )
		    {
			$replaced->{ $ointr->topic->id } = $ointr;
			delete $sum_idx->{ $ointr->topic->id };
			$sum_idx->{ $topic->id } = $in;
			$sum_cnt = scalar keys %$sum_idx;
		    }
		}
	    }
	    debug(-1);
	}
    }

    return [ sort { $a->topic->desig cmp $b->topic->desig } values %$sum_idx ];
}

sub list_item
{
    my( $ins, $item ) = @_;

    $ins->init_list unless $ins->{'list'};

    my $rec = $ins->{'list'}[ $item ];
#    warn "Returning interest no $item: ".Dumper($rec);

    return undef unless $rec;

    return $ins->{'db'}{ $rec->{'intrest_topic'} } ||=
	Para::Interest->new( $rec );
}


sub add
{
    my( $ins, $t ) = @_;

    # TODO: use $ins db
    Para::Interest->touch( $ins->member, $t );
}

sub get
{
    my( $ins, $t ) = @_;

    unless( ref $t )
    {
	$t = Para::Topic->find_one( $t );
    }

    if( ref $t eq 'HASH' )
    {
	# Called with t=record
	return $ins->{'db'}{ $t->{'intrest_topic'} } ||=
	    Para::Interest->new( $t );
    }

    warn "  get interest $t->{id} (interests)\n";

    
    return $ins->{'db'}{ $t->id } ||=
	Para::Interest->get( $ins->member, $t );
}

sub getset
{
    my( $ins, $t ) = @_;

    unless( ref $t )
    {
	$t = Para::Topic->find_one( $t );
    }

    if( ref $t eq 'HASH' )
    {
	# Called with t=record
	return $ins->{'db'}{ $t->{'intrest_topic'} } ||=
	    Para::Interest->new( $t );
    }

    warn "  getset interest ".$t->id."(interests)\n";

    return $ins->{'db'}{ $t->id } ||= 
	Para::Interest->getset( $ins->member, $t );
}

1;
