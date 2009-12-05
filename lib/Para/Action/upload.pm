package Para::Action::upload;

use strict;
use File::Temp qw( tempfile );
use File::stat;

use LWP::MediaTypes qw( media_suffix read_media_types guess_media_type );
read_media_types("/etc/mime.types");

use Para::Frame::Utils qw( throw );

sub handler
{
    my( $req ) = @_;

    if( $req->user->level < 10 )
    {
        throw('denied', "Du har inte access.");
    }

    my $q = $req->q;

    my $filename_in =  $q->param('file_name')
        or throw('incomplete', "Filnamn saknas");
    my $fh =  $q->upload('file_name')
        or die "No file handler\n";

    $filename = lc($filename_in);

    my $dataref = read_all( $fh );


    return "Image created";
}

sub read_all
{
    my( $fh ) = @_;

    my $buf;
    my $fname; ## Temporary filenames
    my $bufsize = 2048;
    my $data; ### Image data
    while( (my $len = sysread($fh, $buf, $bufsize)) > 0 )
    {
        $data .= $buf;
    }
    close($fh);

    return \$data;
}


sub get_suffix
{
    my( $dataref, $filename ) = @_;

    # Use filename if Image::Info failes

    my $imginfo = image_info( $dataref );
    my $media = $imginfo->{file_media_type};

    $media ||= guess_media_type( $filename )
        or die "$filename: Faild to get media type";

    my $suffix = media_suffix($media);

    unless( $suffix )
    {
        die "Can't find suffix for media $media\n";
    }

    return $suffix;
}


1;
