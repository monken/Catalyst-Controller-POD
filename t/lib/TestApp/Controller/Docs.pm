package TestApp::Controller::Docs;

use strict;
use warnings;
use base 'Catalyst::Controller::POD';


sub test : Local {
    my ( $self, $c ) = @_;

    $c->response->body( "here I am" );
}


1;
