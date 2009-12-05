# -*-cperl-*-
package Para::Action::arctype_update;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw extract_query_params );

use Para::Arctype;

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $u = $req->s->u;

    if( $u->level < 40 )
    {
	throw('denied', "Du har inte access för att ändra arctype");
    }

    my $atid = $q->param('atid')
	or throw('incomplete', "atid param missing");

    my $at = Para::Arctype->new( $atid );


    my $rec = extract_query_params(qw(rel_name rev_name super topic
				      literal description));
    
    my $changes = $at->update($rec);


    # Nothing changed
    return "" unless $changes;

    return "Reltype uppdaterad\n";
}

1;
