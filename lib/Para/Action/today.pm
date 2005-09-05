#  $Id$  -*-perl-*-
package Para::Action::today;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw );

use Para::Topic;

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $u = $req->s->u;

    if( $u->level < 11 )
    {
	throw('denied', "Du har inte access för att ändra ändra MOTD");
    }

    my $statement = $q->param('statement');
    defined $statement or throw('validation',"statement param missing");

    my $m = Para::Member->skapelsen;
    $m->set_field('presentation', $statement );

    Para::Widget::new_entry(undef, 'static');
    $Para::MOTD = Para::Widget::html_psi( $m->presentation );

    return "MOTD changed";
}

1;
