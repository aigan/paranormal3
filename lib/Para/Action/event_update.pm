# -*-cperl-*-
package Para::Action::event_update;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw );

use Para::Event;

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $u = $req->s->u;

    if( $u->level < 42 )
    {
	throw('denied', "Reserverat för sysadmin");
    }

    my $eid = $q->param('eventid');
    my( $e );
    my $msg = "";

    my $params = {};
    foreach my $key (keys %Para::Event::FIELDMAP)
    {
	if( $q->param($key) )
	{
	    $params->{$key} = $q->param($key);
	}
    }

    if( $eid )
    {
	$e = Para::Event->get_by_id( $eid );
	$e->update($params) and
	    $msg .= "Uppdaterade event $eid";
    }
    else
    {
	$e = Para::Event->create($params);
	$eid = $e->id;
	$msg .= "Skapade event $eid";
    }

    $q->param('eventid', $eid);
    return $msg;    
}

1;
