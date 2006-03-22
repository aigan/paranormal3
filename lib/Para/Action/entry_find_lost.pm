#  $Id$  -*-perl-*-
package Para::Action::entry_find_lost;

use strict;
use Data::Dumper;

use Para::Frame::Utils qw( throw );

use Para::Constants qw( $C_T_LOST_ENTRY );
use Para::Topic;

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $u = $req->s->u;

    if( $u->level < 12 )
    {
	throw('denied', "Du måste bli väktare för att göra detta");
    }

    my $recs = $Para::dbix->select_list("select t, t_ver from t myouter where t_entry is true and t_entry_parent is null and not exists (select t from t where t_entry_next=myouter.t)");

    my $cnt = 0;
    my $result = "";
    my $lost = Para::Topic->get_by_id( $C_T_LOST_ENTRY );
    foreach my $rec ( @$recs )
    {
	$cnt++;
	my $t = Para::Topic->get_by_id( $rec->{'t'}, $rec->{'t_ver'} );
	$result .= $t->set_parent( $lost );
    }

    return "Lokaliserade $cnt nya texter\n$result";
}

1;
