#  $Id$  -*-perl-*-
package Para::Action::interest_update;

use strict;

use Para::Frame::Utils qw( throw store_params clear_params
			   restore_params );

use Para::Member;

sub handler
{
    my( $req ) = @_;

    my @fields = ();
    my @values = ();


    my $q = $req->q;
    my $u = $req->s->u;

    my $tid = $q->param('tid')
	or throw('incomplete', "tid param missing\n");
    my $mid = $q->param('mid') || $u->id;
    my $m = Para::Member->get($mid);
    my $t = Para::Topic->get($tid);

    if( $u->level < 40 and $u->id != $mid )
    {
	throw('denied', "Du har inte access för att ändra någon annans intressen.");
    }

    warn "  Will now update interest in $tid for $mid\n";

    my $i = Para::Interest->getset( $m, $t );

    if( $i->update_by_query )
    {
	return sprintf( "Nya uppgifter om intresset %s sparat för %s.\n",
			$t->desig, $m->desig);
    }
    return "";
}

1;
