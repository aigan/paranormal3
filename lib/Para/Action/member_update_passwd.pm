# -*-cperl-*-
package Para::Action::member_update_passwd;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw );

use Para::Member;

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $u = $req->s->u;

    my $mid = $q->param('mid') or throw('incomplete', "mid param missing\n");

    my $admin = ( $u->level >= 41 )? 1:0;

    if( not $admin and $u->id != $mid )
    {
	throw('denied', "Du har inte access för att ändra någon annans lösenord.");
    }

    my $m =  Para::Member->get( $mid );

    my $change = $m->change->reset;

    $m->set_passwd( $q->param('passwd_old')||'',
		    $q->param('passwd')||'',
		    $q->param('passwd_confirm')||'',
		    );


    if( $change->changes )
    {
	$req->result->message( $change->message );
    }

    if( $change->errors )
    {
	throw('validation', $change->errmsg );
    }

    return "";
}

1;
