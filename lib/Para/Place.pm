#  $Id$  -*-perl-*-
package Para::Place;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se Place class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use strict;
use Data::Dumper;
use Carp;

BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Utils qw( trim throw debug retrieve_from_url );

sub new
{
    my( $this, $type, $rec, $no_cache ) = @_;
    my $class = ref($this) || $this;
    # $rec can be provided as a mean for optimization

    confess "type param missing" unless $type;
    confess "rec param missing" unless $rec;

    my( $id, $p );

    if( $rec =~ /^\d+$/ )
    {
	$id = $rec;
	$rec = undef;
    }

    if( not $no_cache or not $rec )
    {
	if( exists $Para::Place::CACHE->{type}{$id} )
	{
	    return $Para::Place::CACHE->{type}{$id};
	}
    }

    unless( $rec )
    {
	my $st = "select * from $type where $type=?";
	my $sth = $Para::dbh->prepare( $st );
	$sth->execute( $id );
	$rec =  $sth->fetchrow_hashref;
	$sth->finish;
    }

    if( $rec )
    {
	$p = $Para::Place::CACHE->{$id} = bless($rec, $class);
    }
    else
    {
	$p = $Para::Place::CACHE->{$id} = undef;
    }

    $p->{'geo_x'} = $p->{$type.'_x'};
    $p->{'geo_y'} = $p->{$type.'_y'};
    $p->{'type'}  = $type;
    $p->{'name'} = $p->{$type.'_name'};
    $p->{'l'}    = $p->{$type.'_l'};        # County
    $p->{'lk'}   = $p->{$type.'_lk'};       # Municipality

    return $p;
}

sub type
{
    my( $p ) = @_;
    return $p->{'type'};
}

sub geo_x
{
    my( $p ) = @_;
    return $p->{'geo_x'};
}

sub geo_y
{
    my( $p ) = @_;
    return $p->{'geo_y'};
}

sub equals
{
    my( $p, $p2 ) = @_;

    return 0 unless ref $p2;
    return 0 unless $p->type eq $p2->type;

    if( $p->id == $p2->id )
    {
	return 1;
    }
    else
    {
	return 0;
    }
}

sub county
{
    my( $p ) = @_;

    unless( $p->{'county'} )
    {
	if( my $l = $p->{'l'} )
	{
	    $p->{'county'} = $p->new('county', $l);
	}
	else
	{
	    $p->{'county'} = $p->municipality->county;
	}
    }

    return $p->{'county'};
}

sub municipality
{
    my( $p ) = @_;

    unless( $p->{'municipality'} )
    {
	if( my $lk = $p->{'lk'} )
	{
	    $p->{'municipality'} = $p->new('municipality', $lk);
	}
	else
	{
	    $p->{'municipality'} = $p->zip->municipality;
	}
    }

    return $p->{'municipality'};
}

sub zip
{
    my( $p ) = @_;

    unless( $p->{'zipobj'} )
    {
	if( my $code = $p->{'address_zip'} )
	{
	    $p->{'zipobj'} = $p->new('zip', $code);
	}
	else
	{
	    throw('notfound', "Hittar inte adressen");
	}
    }

    return $p->{'zipobj'};
}

sub desig
{
    my( $p ) = @_;

    return $p->name;
}

sub name
{
    my( $p ) = @_;

    return $p->{'name'};
}

sub aproximate_street
{
    my( $p ) = @_;

    unless( $p->{'aprox_street'} )
    {
	if( $p->{'address_street'} )
	{
	    $p->{'aprox_street'} =
		$p->new('street', $p->{'address_street'});
	}
	elsif( $p->{'street'} )
	{
	    return $p;
	}
	elsif( $p->{'zip'} )
	{
	    my $streetlist = $Para::dbix->select_list("select street, street_name, address_nr_from, address_nr_to from street, address where address_street=street and address_zip=?", $p->{'zip'});
	    $p->{'aprox_street'} = $p->new('street', $streetlist->[0]{'street'});
	}
	else
	{
	    $p->{'aprox_street'} = $p->aproximate_zip->aproximate_street;
	}
    }

    return $p->{'aprox_street'};
}

sub aproximate_zip
{
    die "not implemented";
}

#################################################################

sub by_zip ## Returns zip place object
{
    my( $this, $code ) = @_;

    return unless $code;

    warn "Looking up zip $code\n";

    if( $code =~ m/^(se?-)?[\d\s]+$/i ) # Zip code
    {
	$code =~ s/\D//g;
	warn "Returning zip object\n";
	return $this->new('zip', $code);
    }

    return undef;
}

sub by_name  ## LIST CONSTRUCTOR
{
    my( $this, $identity, $complete ) = @_;
    my $class = ref($this) || $this;

    my @places;

    trim( \$identity );
    $identity = lc( $identity );

    my $found = 0;

    if( $identity eq 'här' )
    {
	$identity = $Para::Frame::U->home_postal_code;
    }

    if( $identity =~ m/^(se?-)?[\d\s]+$/i ) # Zip code
    {
	$identity =~ s/\D//g;
	push @places, $this->new('zip', $identity);
    }
    else # City
    {
	if( my $rec = $Para::dbix->select_possible_record("from city where lower(city_name)=?", $identity) )
	{
	    push @places, $this->new('city', $rec);
	}

	if( $complete or not $found )
	{
	    # Add county search
	}

	if( $complete or not $found )
	{
	    # add other search...
	}
    }

    my @sorted = sort { lc($a->{'name'}) cmp lc($b->{'name'}) } @places;

    return \@sorted;
}

########################################################################

######## Class methods #######################

sub fix_zipcodes
{
    #### Decide for the most worthy address
    #
    # 1. streetname
    # 2. zipcode
    if( my $zip = worthy_zip() )
    {
	debug "Got zip $zip";

	#### Is the zipcode imported?
	unless( exist_zip( $zip ) )
	{
	    debug "Importing $zip";
	    import_zip( $zip ) or remove_zip( $zip ) and return;
	}

	my( $x, $y ) = get_coord_zip( $zip );

	if( $x )
	{
	    debug "X $x, Y $y\n";
	    store_coord_zip( $x, $y, $zip );
	}
	else
	{
	    debug "ERROR: Set zip to null\n";
	    update_zip( undef, undef, $zip, 0 );
	}
    }
}


sub remove_zip
{
    my( $zip ) = @_;
    debug "Illegal zip";

    my $list = $Para::dbix->select_list('from member where home_postal_code=?', "S-$zip");
    foreach my $rec ( @$list )
    {
	my $m = Para::Member->get_by_id( $rec->{'member'}, $rec );
	$m->set_home_postal_code('');
    }

    return 1;
}

sub store_coord_zip
{
    my( $x, $y, $zip ) = @_;

    ## Store zip, city, county, member

    # Precisions
    # 0. Undefined
    # 1. country
    # 2. county
    # 3. city
    # 4. ---
    # 5. zip
    # 6. street
    # 7. address

    update_zip( $x, $y, $zip, 5 );
    update_city_zip( $zip );
}

sub update_zip
{
    my( $x, $y, $zip, $precision ) = @_;

    $precision ||= 0;

    my $sth_zip = $Para::dbh->prepare(
	  "update zip set zip_x=?, zip_y=?, zip_precision=?
           where zip=? and (zip_precision>? or zip_precision is null)" );
    $sth_zip->execute($x, $y, $precision, $zip, $precision);

    my $list = $Para::dbix->select_list("from member where home_postal_code=? and (geo_precision<5 or geo_precision is null)", "S-$zip");
    foreach my $rec (@$list)
    {
	my $m = Para::Member->get_by_id( $rec->{'member'}, $rec );
	$m->set_geo( $x, $y, $precision );
    }
}

sub update_city_zip
{
    my( $zip ) = @_;

    my $sth_city = $Para::dbh->prepare(
	  "select city, city_name from city, zip where zip=? and zip_city=city");
    $sth_city->execute($zip);
    my( $city, $city_name ) = $sth_city->fetchrow_array;
    $sth_city->finish;


    my $sth_check = $Para::dbh->prepare(
	  "select city_precision from city where city=?");
    $sth_check->execute($city);
    my( $old_precision ) = $sth_check->fetchrow_array;
    $old_precision ||= 8;
    if( $old_precision > 4 ) # Calculat middle point
    {
	my $sth_zip = $Para::dbh->prepare(
	      "select zip_x, zip_y from zip where zip_city=?");
	$sth_zip->execute($city);
	my( $x, $y, $cnt ) = 0;
	while( my $rec = $sth_zip->fetchrow_hashref )
	{
	    if( $rec->{'zip_x'} )
	    {
		$x += $rec->{'zip_x'};
		$y += $rec->{'zip_y'};
		$cnt ++;
	    }
	}
	$sth_zip->finish;
	$x = $x / $cnt;
	$y = $y / $cnt;

	# Update city
	my $sth_city = $Para::dbh->prepare(
	      "update city set city_x=?, city_y=?, city_precision=3
               where city=?" );
	$sth_city->execute($x, $y, $city);

	# update users
	my $list = $Para::dbix->select_list("from member where home_postal_city=? and (geo_precision<4 or geo_precision is null)", $city_name);
	foreach my $rec (@$list)
	{
	    my $m = Para::Member->get_by_id( $rec->{'member'}, $rec );
	    $m->set_geo( $x, $y, 3 );
	}
    }
}

sub get_city_zip
{
    my( $zip ) = @_;

    my $sth = $Para::dbh->prepare("select city_name from city, zip where zip=? and zip_city=city");
    $sth->execute($zip);
    my( $city_name ) = $sth->fetchrow_array;
    $sth->finish;
    return $city_name;
}

sub get_first_address_zip
{
    my( $zip ) = @_;

    my $sth = $Para::dbh->prepare("select street_name, address_nr_from from street, address where address_street=street and address_zip=?");
    $sth->execute($zip);
    my( $street_name, $nr ) = $sth->fetchrow_array;
    $sth->finish;
    return( $street_name, $nr );
}

sub get_coord_zip
{
    my( $zip ) = @_;


    my( $city ) = get_city_zip( $zip ) or return;
    my( $x, $y, $page, $url );
 
    debug "Getting coordinates for $zip";
    my $streetlist = $Para::dbix->select_list("select street_name, address_nr_from, address_nr_to from street, address where address_street=street and address_zip=?", $zip);

  STREET:
    foreach my $rec (@$streetlist)
    {
	my $street = $rec->{'street_name'};
	my $nr1    = $rec->{'address_nr_from'};
	my $nr2    = $rec->{'address_nr_to'};

	my @nrs = ( $nr1 );
	push @nrs, $nr2 if $nr2 and $nr2 < 1000;

	foreach my $nr ( @nrs )
	{

	    my $ecity = CGI::escape( $city );
	    my $streetnr;
	    if( $nr and $nr > 0 )
	    {
		$streetnr = "$street $nr";
	    }
	    else
	    {
		$streetnr = $street;
	    }

	    debug "Getting coordinates for $streetnr, $city";
	    my $estreet = CGI::escape( $streetnr );
	    
	    $url = "http://www.infospace.com/mapredir.htm?&QA=$estreet&QC=$ecity&QO=SE&s=2";
	    $page = retrieve_from_url($url);
#		or die "ERR: Getting coord page $url for $ecity $estreet failed\n";

	    ( $y ) = $page =~ /NAME="lat" VALUE="(.*?)"/;
	    ( $x ) = $page =~ /NAME="long" VALUE="(.*?)"/;


#
#  BERGAV%C4GEN+0   G%D6TEBORG
#
# http://www.infospace.com/mapredir.htm?&QA=BERGAV%C4GEN+0&QC=G%D6TEBORG&QO=SE&s=2
# Sorry, the system was unable to map

	    if( $x and $y )
	    {
		last STREET;
	    }

	    $Para::Frame::REQ->yield(4); # Wait for a while
	}
    }

    unless( $y and $x )
    {
	# the system was unable to map
	# <!--inc_abbrtostate.htm-->
	if( $page =~ /the system was unable to map/ )
	{
	    debug "ERROR: Zip $zip not a location\n";
	    debug "Result from page $url\n";
	    ## Remove zip, since it's not a location
	    my $sth_zip = $Para::dbh->prepare(
           "update zip set zip_precision=null where zip=?" );
	    $sth_zip->execute($zip);
	    return undef;
	}
	else
	{
	    debug "ERROR: Failed to retrieve coordinates.  Page:\n\n";
	    die $page;
	}
    }

    return( $x, $y );
}

sub import_zip
{
    my( $zip ) = @_;

    my( $city, $lk, $city_name );

    my $page = retrieve_from_url("http://www.leissner.se/cgi/postnr2?postnr=$zip");
    #or die "ERR: Getting zip page failed\n";
#    use File::Slurp;
#    my $page = read_file("/var/www/paranormal.se/cgi/data/postnr_test.txt");

    foreach my $row ( split /\n/, $page )
    {
	$row =~ m/^<TR><TD>(.*?)<\/TD><TD>(.*?)<\/TD><TD>(.*?)<\/TD><TD>(.*?)<\/TD><TD>(.*?)<\/TD><TD>(.*?)<\/TD><TD>(.*?)<\/TD><\/TR>/
	  or next;

	my $gatunamn = $1;
	my $gatunr = $2;
	my $postnr = $3;
	$city_name = $4;
	my $lan = $5;
	$lk = $6; # Kommun
	my $areg = $7;

#	print "($gatunamn)($gatunr)($postnr)($lan)($lk)($areg)\n";

	my($from, $to) = split /-/, $gatunr;

	$from ||= 0;
	$to ||= $from;
	if( $to )
	{
	    $to = 10000 if $to > 10000;
	}
	my $step = $to ? 2 : 1;
	if( $from )
	{
	    $from = ($from % $step)+1 if $from > 10000;
	}

	my( $county ) = $lan =~ /(\d+)/;
	$city = get_city($city_name, $county, $areg);
	my $street = get_street( $gatunamn, $city, $from, $to );

	my $sth = $Para::dbh->prepare(
	      "insert into address
               (address_street, address_nr_from, address_nr_to, address_step, address_zip)
               values (?,?,?,?,?)");
#	print "--- $street, $from, $to, $step, $postnr\n";
	$sth->execute($street, $from, $to, $step, $postnr );


	# This may commit data half way through
	$Para::Frame::REQ->may_yield;
    }

    $city_name or return undef;

    my $sth_zip = $Para::dbh->prepare(
	  "insert into zip
          (zip, zip_city, zip_lk)
          values (?,?,?)");
    $sth_zip->execute($zip, $city, $lk );

    # Update all members with zip
    my $list = $Para::dbix->select_list("from member where home_postal_code = ?", "S-$zip");
    foreach my $rec (@$list)
    {
	my $m = Para::Member->get_by_id( $rec->{'member'}, $rec );
	$m->{'home_postal_city'} = $city_name;
	$m->mark_unsaved;
    }

    return 1;
}

sub get_city
{
    my( $city_name, $city_l, $city_areg ) = @_;

    my $sth_read = $Para::dbh->prepare(
	  "select * from city where city_name = ?");
    $sth_read->execute($city_name);

    my $city;
    if( my $rec = $sth_read->fetchrow_hashref )
    {
	# update record
	$city = $rec->{'city'};
	my $sth_update = $Para::dbh->prepare(
	      "update city set city_l=?, city_areg=?
               where city=?");
	$sth_update->execute($city_l, $city_areg, $city );
    }
    else
    {
	# create record
	$city = $Para::dbix->get_nextval('city_seq');

	my $sth_create = $Para::dbh->prepare(
	      "insert into city
                      (city, city_name, city_l, city_areg)
               values (?, ?, ?, ? )");
	$sth_create->execute( $city, $city_name, $city_l, $city_areg );
    }
    $sth_read->finish;
    return $city;
}

sub get_street
{
    my( $street_name, $city, $from, $to ) = @_;

    my $sth_read = $Para::dbh->prepare(
	  "select * from street where street_name = ? and street_city = ?");
    $sth_read->execute($street_name, $city);

    if( $to )
    {
	debug "Street $street_name ( $from - $to )";
    }
    else
    {
	debug "Street $street_name";
    }

    my $street;
    if( my $rec = $sth_read->fetchrow_hashref )
    {
	# update record

	my $old_from = $rec->{'street_nr_from'};
	if( $old_from and $from )
	{
	    $from = $old_from if $old_from < $from;
	}
	elsif( $old_from )
	{
	    $from = $old_from;
	}

	$to ||= 0;
	my $old_to = $rec->{'street_nr_to'} || 0;
	$to   = $old_to  if $old_to   > $to;

	$street = $rec->{'street'};

	my $sth_update = $Para::dbh->prepare(
	      "update street set street_nr_from=?, street_nr_to=?
               where street=? and street_city=?");
	$sth_update->execute($from, $to, $street, $city );
    }
    else
    {
	# create record
	$street = $Para::dbix->get_nextval('street_seq');

	my $sth_create = $Para::dbh->prepare(
	      "insert into street
                      (street, street_nr_from, street_nr_to,
                      street_name, street_city)
               values (?, ?, ?, ?, ? )");

#	warn "$street, $from, $to, $street_name, $city\n";

	$street_name = substr( $street_name, 0, 31);

	$sth_create->execute( $street, $from, $to, $street_name, $city );
    }
    $sth_read->finish;
    return $street;
}

sub exist_zip
{
    my( $zip ) = @_;

    my $sth = $Para::dbh->prepare("select * from zip where zip = ?");
    $sth->execute($zip);
    my $rows = $sth->rows;
    $sth->finish;
    return $rows;
}

sub worthy_zip
{
    my $sth = $Para::dbh->prepare(
	  "select * from member
           where home_postal_code is not null and
                 ((geo_precision < 4 and geo_precision>0) or geo_precision is null ) and
                 home_postal_code like 'S-%'
           order by member_level desc, geo_precision, member
           limit 1");
    $sth->execute();
    my $m = $sth->fetchrow_hashref;
    $sth->finish;
    $m or return undef; # Out of zip-codes!

    debug sprintf( "Member %s %s, level %d was proven worthy enough\n",
		   $m->{'member'}, $m->{'nickname'},  $m->{'member_level'});

    my $zip = $m->{'home_postal_code'};
    substr($zip,0,2,'');
    return $zip;
}


1;
