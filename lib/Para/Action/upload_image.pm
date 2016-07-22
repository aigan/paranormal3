package Para::Action::upload_image;

use strict;
use Imager 0.41;
use File::Temp qw( tempfile );
use Image::Info qw( image_info);
use File::stat;
use IO::File;
use Data::Dumper;
use File::Slurp;								# exports read_file

use constant SIZESCALE => 200;
use constant SIZETHUMB => 60;
use constant MEDIATYPE => 'image/png';

use LWP::MediaTypes qw( media_suffix read_media_types guess_media_type );
read_media_types("/etc/mime.types");

use Para::Frame::Utils qw( debug throw create_dir chmod_file );

sub handler
{
	my( $req ) = @_;

	if ( $req->user->level < 10 )
	{
		throw('denied', "Du har inte access.");
	}

	my $q = $req->q;

	my $tid = $q->param('tid') || die "tid missing";

	my $t = Para::Topic->get_by_id($tid) or die "Couldn't find tid $tid";


	my $filename =  $q->param('file_name')
		or throw('incomplete', "Filnamn saknas");

	my $infile = $req->uploaded('file_name')->tempfile;
	debug "Infile is $infile";

	my $dataref = $infile->content;
	debug "Dataref is $dataref";

	my $img = {};

	$img->{'orig'}   = get_image($dataref);
	$img->{'scaled'} = $img->{'orig'}->scale(xpixels=>SIZESCALE);
	$img->{'thumb'}  = $img->{'scaled'}->scale(ypixels=>SIZETHUMB);

	my $dir_base = "/var/www/paranormal.se/images/db";
	my $dir = $dir_base.'/'.$tid.'/';
	create_dir( $dir, {umask=>0});

	foreach my $variant ( keys %$img )
	{
		my $file_out = $dir.$variant.'.png';
		debug "Storing image as: $file_out\n";
		$img->{$variant}->write(file=>$file_out) or
	    die $img->{$variant}->errstr;
		chmod_file( $file_out, {umask=>0});
	}



	#### Set topic

	my $mime_str = "image/png";
	my $url_str = "/images/db/$tid/scaled.png";

	$t->media_set($url_str, $mime_str);


#    my $dbh = $req->app->dbix->dbh;
#    my $code = $q->param('image_code') or die ['validate', "Code missing\n"];
#    my( $scaled_oid, $scaled_size ) = create_blob( $req, $scaled, $suffix );
#    my( $thumb_oid, $thumb_size ) = create_blob( $req, $thumb, $suffix );
#    my $sth_image = $dbh->prepare_cached("insert into image (image_code,
#  image_type, image_data, image_data_x, image_data_y, image_data_size,
#  image_thumb, image_thumb_x, image_thumb_y, image_thumb_size,
#  image_updated) values ( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, now() )");
#    $sth_image->execute(
#                        $code,
#                        MEDIATYPE,
#                        $scaled_oid,
#                        $scaled->getwidth(),
#                        $scaled->getheight(),
#                        $scaled_size,
#                        $thumb_oid,
#                        $thumb->getwidth(),
#                        $thumb->getheight(),
#                        $thumb_size,
#                        );
#    $q->param('id', $code);

	return "Image created";
}

sub read_all
{
	my( $fh_in ) = @_;

	my $fh = new IO::File $fh_in, "r"
		or die "Could not read from $fh_in: $!";

	my $buf;
	my $fname;										## Temporary filenames
	my $bufsize = 2048;
	my $data;											### Image data
	while ( (my $len = sysread($fh, $buf, $bufsize)) > 0 )
	{
		$data .= $buf;
	}
	close($fh);

	return \$data;
}

sub get_image
{
	my( $file ) = @_;

	my( $dataref, $suffix );
	if ( ref $file )
	{
		$dataref = $file;
		$suffix = get_suffix($dataref);
	}
	else
	{
		my $data = read_file($file);
		$dataref = \$data;
		$suffix = get_suffix($dataref, $file);
	}

	my $img = Imager->new();
	unless( $img->read(data=>$$dataref, type => $suffix ) )
	{
		# We faild reading the image
		# Call upon the immense power of ImageMagick!
		#
		warn $img->errstr;

		my $size = length($$dataref);
		unless( $size )
		{
			die "Dataref has no size\n";
		}
		warn "$$: Size of dataref is $size\n";

		require Image::Magick;
		my $p = new Image::Magick;
		$p->BlobToImage( $$dataref );

		my( $fh, $fname ) = tempfile();
		$p->Write( file => $fh, magick => 'png' );

		seek( $fh, 0, 0 );					# Back to start

		warn "New atempt to read file $fname via fh\n";
		$img->read(fh=>$fh, type => 'png' )
			or die $img->errstr;
	}
	return $img;
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

sub create_blob
{
	my( $req, $img, $suffix ) = @_;
	$suffix ||= 'jpg';

	my( $fh, $fname ) = tempfile();
	$img->write(fd=>fileno($fh), type=>$suffix)
		or die $img->errstr;

	seek( $fh, 0, 0 );						# Back to start

	my $size = stat($fh)->size;
	warn "Blob with size $size\n";

	my $oid = $req->app->dbh->func($fname, 'lo_import')
		or die "$fname: import failed\n";

	return( $oid, $size );
}

1;
