# -*-cperl-*-
package Para::Action::arctype_create;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw );

use Para::Arctype;

sub handler
{
	my( $req ) = @_;

	my $q = $req->q;
	my $u = $req->session->user;

	if ( $u->level < 40 )
	{
		throw('denied', "Du har inte access för att skapa reltype");
	}

	my $type = Para::Arctype->create();

	my $atid = $type->id;

	$q->param('atid', $atid);

	return "Ny arctype skapad";
}

1;
