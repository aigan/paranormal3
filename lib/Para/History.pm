#  $Id$  -*-perl-*-
package Para::History;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se eventy history
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
use Para::Frame::DBIx;
use Para::Frame::Time;

use Para::Topic;
use Para::Constants qw( :all );

sub begin
{
#    $Para::query->param('history_partof', get_nextval('history_seq'));
}

sub add
{
    my( $this, $hclass, $action, $args ) = @_;

    my $id = $Para::dbix->get_nextval('history_seq');
    my $status = $args->{status} || HS_CREATED;
    my $created = localtime;
    my $createdby = $args->{createdby} || $Para::Frame::U;
    my $secret = $args->{secret} || 0;
    my $partof = $args->{partof};
    $partof ||= $Para::query->param('history_partof') if $ENV{MOD_PERL};

    my $topic = $args->{topic} || undef;
    my $topic_id = $topic ? $topic->id : undef;
    my $member = $args->{member};
    my $member_id = $member ? $member->id : undef;
    my $skey = $args->{skey};
    my $slot = $args->{slot};
    my $vold = $args->{vold};
    my $vnew = $args->{vnew};
    my $comment = $args->{comment};
 

    my $sth = $Para::dbh->prepare("insert into history (
                          history_id, history_status, history_created,
                          history_createdby, history_secret,
                          history_partof, history_topic,
                          history_member, history_class,
                          history_action, history_skey, history_slot,
                          history_vold, history_vnew, history_comment
                          ) values ( ?, ?, ?, ?, ?, ?, ?, ?, ?,
                          ?, ?, ?, ?, ?, ? )");

#    $sth->execute($id, $status, $created->cdate, $createdby->id,
#		  pgbool($secret), $partof, $topic_id, $member_id,
#		  $hclass, $action, $skey, $slot, $vold, $vnew,
#		  $comment);

}

1;
