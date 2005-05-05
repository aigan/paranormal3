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
    warn "  Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;
use Para::Topic;

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

sub rel_list
{
    my( $this, $tid ) = @_;

    my $recs = $Para::dbix->select_list("from ts where ts_entry=? and ts_active is true", $tid);

    my @tss;

    foreach my $rec ( @$recs )
    {
	push @tss, Para::TS->new( $rec );
    }
    return \@tss;
}

sub rev_list
{
    my( $this, $tid ) = @_;

    my $recs = $Para::dbix->select_list("from ts where ts_topic=? and ts_active is true", $tid);

    my @tss;

    foreach my $rec ( @$recs )
    {
	push @tss, Para::TS->new( $rec );
    }
    return \@tss;
}

sub topic
{
    Para::Topic->new( shift->{'ts_topic'} );
}

sub entry
{
    Para::Topic->new( shift->{'ts_entry'} );
}

sub comment { shift->{'ts_comment'} };

sub active
{
    die "not implemented";
}

1;
