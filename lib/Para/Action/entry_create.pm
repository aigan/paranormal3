#  $Id$  -*-perl-*-
package Para::Action::entry_create;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw trim );
use Para::Utils qw( trim_text );

use Para::Topic;

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $u = $req->s->u;

    if( $u->level < 5 )
    {
	throw('denied', "Du måste bli medborgare för att få skapa nya texter");
    }

    my $new_text = $q->param('t_text')
	or throw('incomplete', "t_text param missing");

    my $parent = $q->param('tid')
	or throw('incomplete', "tid param missing");

    trim_text( \$new_text );

    return "" unless length( $new_text );

    my $changes = $req->change;

    my $t = Para::Topic->create_entry($parent, \$new_text);

    $changes->note("Ändringen kommer att kontrolleras\n");

    $q->param('tid', $t->id);

    return "Ny text skapad";
}

1;
