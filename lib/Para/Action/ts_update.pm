#  $Id$  -*-perl-*-
package Para::Action::ts_update;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw debug trim clear_params );
use Para::Frame::Widget qw( jump rowlist );

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
    my $site = $req->site;

    my $tswords = rowlist('_meta_talias');
    if( @$tswords )
    {
	debug "Found topicalias list";
	my $new = {};
	foreach my $row ( @$tswords )
	{
	    my $t;
	    eval
	    {
		$t = Para::Topic->find_one( $row );
	    };
	    if( $@ )
	    {
		if( ref $@ and $@->[0] eq 'alternatives' )
		{
		    my $res = $req->result;
		    my $alt = $res->{'info'}{'alternatives'} ||= {};

		    my $block;
		    foreach my $oldrow ( @$tswords )
		    {
			if( $row ne $oldrow )
			{
			    $block .= $oldrow."\n";
			}
		    }

		    $alt->{'rowformat'} = sub
		    {
			my( $t ) = @_;
			
			my $tid = $t->id;
			my $ver = $t->ver;

			my $val = $block . $tid ." ".$t->desig;

			my $replace = $alt->{'replace'} || '_meta_talias';
			my $view = $alt->{'view'} || '/member/db/topic/edit/topicstatements.tt';
			
			return sprintf( "<td>%s <td>%d v%d <td>%s <td>%s",
					jump('välj',
					     $view,
					     {
						 step_replace_params => $replace,
						 $replace => $val,
						 run => 'next_step',
						 class => 'link_button',
					     }),
					$t->id,
					$ver,
					$t->link,
					$t->type_list_string,
					);
		    };

		    $req->page->set_error_template($site->home.'/alternatives.tt');
		    $req->s->route->bookmark;
		}
		die $@; # Propagate error
	    }

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
