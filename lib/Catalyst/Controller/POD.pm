package Catalyst::Controller::POD;
use warnings;
use strict;
use File::Find qw( find );
use File::ShareDir qw( dist_file );
use File::Spec;
use File::Slurp;
use Pod::Simple::Search;
use JSON::XS;
use Pod::POM;
use XML::Simple;
use LWP::Simple;
use List::MoreUtils qw(uniq);



use lib(qw(/Users/mo/Documents/workspace/Catalyst-Controller-POD/lib));
use Catalyst::Controller::POD::Template;

use base "Catalyst::Controller::POD::Search";

__PACKAGE__->mk_accessors(qw(_dist_dir inc namespaces self dir));

__PACKAGE__->config(
 self => 1,
 namespaces => ["*"]
);


=head1 NAME

Catalyst::Controller::POD - Serves PODs right from your Catalyst application

=head1 VERSION

Version 0.02

=cut
our $VERSION = '0.02006';

=head1 SYNOPSIS

Create a new controller and paste this code:

  package MyApp::Controller::YourNewController;  # <-- Change this to your controller
  
  use strict;
  use warnings;
  use base 'Catalyst::Controller::POD';
  __PACKAGE__->config(
    inc        => 1,
    namespaces => [qw(Catalyst::Manual*)],
    self       => 1,
    dirs       => [qw()]
  );
  1;

=head1 DESCRIPTION

This is a catalyst controller which serves PODs. It allows you to browse through your local
repository of modules. On the front page of this controller is a search box
which uses CPAN's xml interface to retrieve the results. If you click on one of them
the POD is displayed in this application.

Cross links in PODs are resolved and pop up as a new tab. If the module you clicked on is
not installed this controller fetches the source code from CPAN and creates the pod locally.
There is also a TOC which is always visible and scrolls the current POD to the selected section.

It is written using a JavaScript framework called ExtJS (L<http://www.extjs.com>) which
generate beautiful and intuitive interfaces.

Have a look at L<http://cpan.org/authors/id/P/PE/PERLER/pod-images/pod-encyclopedia-01.png>

=head1 CONFIGURATION

=over

=item inc (Boolean)

Search for modules in @INC. Set it to 1 or 0.

Defaults to C<0>.

=item namespaces (Arrayref)

Filter by namespaces. See L<Pod::Simple::Search> C<limit_glob> for syntax.

Defaults to C<["*"]>

=item self (Boolean)

Search for modules in C<< $c->path_to( 'lib' ) >>.

Defaults to C<1>.

=item dirs (Arrayref)

Search for modules in these directories.

Defaults to C<[]>.

=head1 NOTICE

This module works fine for most PODs but there are a few which do not get rendered properly. 
Please report any bug you find. See L</BUGS>.

Have a look at L<Pod::Browser> which is a catalyst application running this controller. You
can use it as a stand-alone POD server.

=cut

sub search : Local {
	my ( $self, $c ) = @_;
	my $k = $c->req->param("value");
	my $s = $c->req->param("start");
	my $url = new URI("http://search.cpan.org/search");
	$url->query_form_hash(
		query  => $k,
		mode   => "module",
		n      => 50,
		format => "xml",
		s      => $s
	);
	my $ua = new LWP::UserAgent;
	$ua->timeout(15);
	$c->log->debug("get url ".$url->canonical) if($c->debug);
	my $response = $ua->get($url);
	my $xml = $response->content;
	my $data;
	eval{ $data = XMLin($xml, keyattr => [] )};
	if(@$) {
		$c->res->body("[]");
		return;
	}
	my $output = {count => $data->{matches}};
	while(my($k,$v) = each %{$output->{module}}) {
		
	}
	$c->res->body(encode_json($data));
}


sub module : Local {
	my ( $self, $c, $module ) = @_;
	my $search = Pod::Simple::Search->new->inc( $self->inc || 0 );
	push( @{ $self->{dirs} }, $c->path_to('lib')->stringify )
	  if ( $self->{self} );
	my $name2path =
	  $search->limit_glob($module)->survey( @{ $self->{dirs} } );
	my $view = "Catalyst::Controller::POD::POM::View";
	Pod::POM->default_view($view);
	my $parser = Pod::POM->new( warn => 0 );
	$view->_root( $self->_root($c) );
	$view->_module($module);
	my $pom;

	if ( $name2path->{$module} ) {
		$c->log->debug("Getting POD from local store") if($c->debug);
		$view->_toc( _get_toc( $name2path->{$module} ) );
		$pom = $parser->parse_file( $name2path->{$module} )
		  || die $parser->error(), "\n";
	} else {
		$c->log->debug("Getting POD from CPAN") if($c->debug);
		my $html = get( "http://search.cpan.org/perldoc?" . $module );
	    my $source;
		if($html && $html =~ /.*<a href="(.*?)">Source<\/a>.*/) {
		    $html =~ s/.*<a href="(.*?)">Source<\/a>.*/$1/s;
    		$c->log->debug("Get source from http://search.cpan.org" . $html) if($c->debug);
    		$source = get( "http://search.cpan.org" . $html );
        } else {
            $source = "=head1 ERROR\n\nThis module could not be found.";
        }
		$view->_toc( _get_toc( $source ) );
		$pom = $parser->parse_text($source)
		  || die $parser->error(), "\n";
	}
	Pod::POM->default_view("Catalyst::Controller::POD::POM::View");
	$c->res->body( "$pom" );
}

sub _get_toc {
	my $source = shift;
	my $toc;
	my $parser = Pod::POM->new( warn => 0 );
	my $view = "Pod::POM::View::TOC";
	Pod::POM->default_view($view);
	my $pom = $parser->parse($source);
	$toc = $view->print($pom);
	return encode_json( _toc_to_json( [], split( /\n/, $toc ) ) );
}

sub _toc_to_json {
	my $tree     = shift;
	my @sections = @_;
	my @uniq     = uniq( map { ( split(/\t/) )[0] } @sections );
	foreach my $root (@uniq) {
		next unless ($root);
		push( @{$tree}, { text => $root } );
		my ( @children, $start );
		for (@sections) {
			if ( $_ =~ /^\Q$root\E$/ ) {
				$start = 1;
			} elsif ( $start && $_ =~ /^\t(.*)$/ ) {
				push( @children, $1 );
			} elsif ( $start && $_ =~ /^[^\t]+/ ) {
				last;
			}
		}
		unless (@children) {
			$tree->[-1]->{leaf} = \1;
			next;
		}
		$tree->[-1]->{children} = [];
		$tree->[-1]->{children} =
		  _toc_to_json( $tree->[-1]->{children}, @children );
	}
	return $tree;
}

sub modules : Local {
	my ( $self, $c, $find ) = @_;
	my $search = Pod::Simple::Search->new->inc( $self->{inc} || 0 );
	push( @{ $self->{dirs} }, $c->path_to('lib')->stringify )
	  if ( $self->{self} );
	my $name2path = {};

		for ( @{ $self->{namespaces} } ) {
			my $found =
			  Pod::Simple::Search->new->inc( $self->{inc} || 0 )
				  ->limit_glob($_)->survey( @{ $self->{dirs} } );
			%{$name2path} = (
				%{$name2path}, %{$found}
			);
		}
	
	my @modules;
	while ( my ( $k, $v ) = each %$name2path ) {
		next if($find && $k !~ /\Q$find\E/ig);
		push( @modules, $k );
	}
	@modules = sort @modules;
	my $json = _build_module_tree( [], "", @modules );
	$c->res->body( encode_json($json) );
}

sub _build_module_tree : Private {
	my $tree    = shift;
	my $stack   = shift;
	my @modules = @_;
	my @uniq    = uniq( map { ( split(/::/) )[0] } @modules );
	foreach my $root (@uniq) {
		my $name = $stack ? $stack . "::" . $root : $root;
		push( @{$tree}, { text => $root, name => $name } );
		my @children;
		for (@modules) {
			if ( $_ =~ /^$root\:\:(.*)$/ ) {
				push( @children, $1 );
			}
		}
		unless (@children) {
			$tree->[-1]->{leaf} = \1;
			next;
		}
		$tree->[-1]->{children} = [];
		$tree->[-1]->{children} =
		  _build_module_tree( $tree->[-1]->{children}, $name, @children );
	}
	return $tree;
}

sub _root {
	my ( $self, $c ) = @_;
	my $index = $c->uri_for( __PACKAGE__->config->{path} );

	#$index  =~ s/\/index//g;
	return $index;
}

sub new {
	my $self = shift;
	my $new  = $self->next::method(@_);
	my $path;
	eval { $path = dist_file( 'Catalyst-Controller-POD', 'docs.js' ); };
	if ($@) {
		# I'm on my local machine
		$path = "/Users/mo/Documents/workspace/Catalyst-Controller-POD/share";
	} else {
		my ( $volume, $dirs, $file ) = File::Spec->splitpath($path);
		$path = File::Spec->catfile( $volume, $dirs );
	}
	$new->_dist_dir($path);
	return $new;
}

sub index : Path : Args(0) {
	my ( $self, $c ) = @_;
	$c->res->content_type('text/html; charset=utf-8');
	$c->response->body(
		Catalyst::Controller::POD::Template->get(
			$self->_root($c) . "/static"
		)
	);
}

sub static : Path("static") {
	my ( $self, $c, @file ) = @_;
	my $file = File::Spec->catfile(@file);
	my $data;
	eval { $data = read_file( $self->_dist_dir . "/" . $file ) };
	if ($@) {
		$c->res->status(404);
		$c->res->content_type('text/html; charset=utf-8');
	} else {
		if ( $file eq "docs.js" ) {
			my $root = $self->_root($c);
			$data =~ s/\[% root %\]/$root/g;
		}
		$c->response->body($data);
	}
}

=head1 TODO

Write more tests!

=head1 AUTHOR

Moritz Onken <onken@houseofdesign.de>

=head1 BUGS

Please report any bugs or feature requests to C<bug-catalyst-controller-pod at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Catalyst-Controller-POD>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Catalyst::Controller::POD


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Catalyst-Controller-POD>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Catalyst-Controller-POD>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Catalyst-Controller-POD>

=item * Search CPAN

L<http://search.cpan.org/dist/Catalyst-Controller-POD>

=back


=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2008 Moritz Onken, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut
1;    # End of Catalyst::Controller::POD
