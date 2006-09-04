#  $Id$  -*-perl-*-
package Para::Action::save_comment;

use strict;

use Para::Frame::Utils qw( throw debug trim datadump );

sub handler
{
    my( $req ) = @_;

    my $q = $req->q;
    my $home_path = $req->site->home->sys_path;

    my $dir_path = $q->param('dir');
    my $base     = $q->param('file');
    my $comment  = $q->param('comment');
    my $path     = $home_path.$dir_path.'/'.$base.'.txt';

    open(FILE, '>', $path) or die "Couldn't save '$path': $!";
    print FILE $comment;
    close FILE;
    return "Sparade kommentaren";
}

1;
