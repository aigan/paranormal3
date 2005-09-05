#  $Id$  -*-perl-*-
package Para::Action::ts_update;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw debug trim clear_params );

use Para::TS;
use Para::Topic;

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $u = $req->s->u;

    $req->{'clear_fields'} = [];

    if( $u->level < 5 )
    {
	throw('denied', "Du måste bli medborgare för att få uppdatera ett ämne");
    }

    my $change = 0;

    my $eid = $q->param('tid')
	or throw('incomplete', "tid param missing");

    my $e = Para::Topic->get_by_id( $eid );

    $change += &check_ts_create( $e );
    $change += &check_ts_edit( $e );

    clear_params(@{$req->{'clear_fields'}});
    $req->{'clear_fields'} = undef;

    if( $change )
    {
	return "TS uppdaterade";
    }
    else
    {
	return "TS oförändrad";
    }
}


sub check_ts_create
{
    my( $e ) = @_;

    # Plan:
    #
    # Get all existing TS
    # Get new topics
    # Forech new topic:
    #   IF existing:
    #      IF inactive and not higher status:
    #         reactivate
    #   ELSE
    #      create new
    #

    my $req = $Para::Frame::REQ;
    my $q = $req->q;
    my $change = 0;

    if( my $val = $q->param('_meta_talias') )
    {
	$q->delete('_meta_talias');
	debug "Found topicalias list";
	my $new = {};
	foreach my $row ( split /\n/, $val )
	{
	    trim(\$row);
	    next unless length($row);

	    my $t = Para::Topic->find_one( $row );
	    $new->{$t->id} ++;
	}

	foreach my $tid ( keys %$new )
	{
	    $change += Para::TS->set( $e, $tid, 1 );
	}

	push @{$req->{'clear_fields'}}, '_meta_talias';
    }
    return $change;
}

sub check_ts_edit
{
    my( $e ) = @_;
    ### _ts__#_ edit  ( the KEY is ts_topic )  Edit EXISTING

    my $req = $Para::Frame::REQ;
    my $q = $req->q;
    my $change = 0;

    for( my $row=1; my $ts_topic_id = $q->param("_ts__${row}_topic"); $row++ )
    {

	my $ts_keep  = $q->param("_ts__${row}_keep")     ? 1 : 0;
	debug "check ts__${row}_topic $ts_topic_id ($ts_keep)";

	push( @{$req->{'clear_fields'}},
	      "_ts__${row}_keep",
	      "_ts__${row}_topic",
	      );

	$change += Para::TS->set( $e, $ts_topic_id, $ts_keep );
    }

    return $change;
}

1;
