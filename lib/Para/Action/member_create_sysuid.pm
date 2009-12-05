# -*-cperl-*-
package Para::Action::member_create_sysuid;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw );

use Para::Topic;

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $u = $req->s->u;

    if( $u->level < 40 )
    {
	throw('denied', "Du har inte access för att ändra sysuid");
    }

    my $mid = $q->param('mid')
	or throw('incomplete', "mid param missing");

        my $m = Para::Member->get_by_id( $mid );

    if( $m->mailbox->exist )
    {
	throw('action', "Mailbox existerar redan");
    }

    $m->set_sys_uid;

    return "Ny brevlåda registrerad";
}

1;
