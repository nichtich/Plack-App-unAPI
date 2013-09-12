use strict;
use warnings;
package Plack::App::unAPI::Impl;
#ABSTRACT: Implementation of unAPI PSGI application
use v5.10.1;

use base qw(Exporter Plack::Middleware::Negotiate);

use Plack::Request;
use Carp qw(croak);

sub new {
    my ($class, %formats) = @_;

    my $self = bless {
        formats => { },
        apps    => { },
    }, ref $class || $class;

    foreach my $name (grep { $_ ne '_' } keys %formats) {
        my ($app, $type, %about) = @{$formats{$name}};
        croak "unAPI format required MIME type" unless $type;

        $self->{apps}->{$name} = $app;
        $self->{formats}->{$name} = { type => $type, %about };
    }

    $self->{formats}->{_} = $formats{_};

    $self->prepare_app;

    $self;
}

sub call {
    my ($self, $env) = @_;
    my $req    = Plack::Request->new($env);
    my $format = $req->param('format') // '';
    my $id     = $req->param('id') // '';

    # TODO: here we could first lookup the resource at the server
    # and sent 404 if no known format was specified

    return $self->formats($id)
        if $format eq '' or $format eq '_';

    my $route = $self->{formats}->{$format};
    if ( !$route || !$self->{apps}->{$format} ) {
        my $res = $self->formats($id);
        $res->[0] = 406; # Not Acceptable
        return $res;
    }

    return $self->formats('')
        if $id eq '' and !($route->{always} // $self->{formats}->{_}->{always});

    my $res = eval {
        $self->{apps}->{$format}->( $env );
    };
    my $error = $@;

    if ( $error ) {
        $error = "Internal crash with format=$format and id=$id: $error";
    } elsif (not is_psgi_response($res)) {
        # we may also check response type...
        $error = "No PSGI response for format=$format and id=$id";
    }

    if ($error) { # TODO: catch only on request
        return [ 500, [ 'Content-Type' => 'text/plain' ], [ $error ] ];
    }

    $res;
}

# checks whether PSGI conforms to PSGI specification
sub is_psgi_response {
    my $res = shift;
    return (ref($res) and ref($res) eq 'ARRAY' and
        (@$res == 3 or @$res == 2) and
        $res->[0] =~ /^\d+$/ and $res->[0] >= 100 and
        ref $res->[1] and ref $res->[1] eq 'ARRAY');
}

sub formats {
    my ($self, $id, $header) = @_;

    my $status = 300; # Multiple Choices
    my $type   = 'application/xml; charset: utf-8';
    my @xml    = ($header // '<?xml version="1.0" encoding="UTF-8"?>');

    push @xml, $id eq '' ?  '<formats>'
                         : "<formats id=\"" . _xmlescape($id) . "\">";

    foreach my $name (sort keys %{ $self->{formats} }) {
        next if $name eq '_';
        my $format = $self->{formats}->{$name};
        my $line = "<format name=\"$name\" type=\"".$format->{type}."\"";
        if ( $format->{docs} ) {
            push @xml, "$line docs=\"" . _xmlescape($format->{docs}) . '" />';
        } else {
            push @xml, "$line />"
        }
    }

    push @xml, '</formats>';

    return [ $status, [ 'Content-Type' => $type ], [ join "\n", @xml] ];
}

sub _xmlescape {
    my $xml = shift;
    if ($xml =~ /[\&\<\>"]/) {
        $xml =~ s/\&/\&amp\;/g;
        $xml =~ s/\</\&lt\;/g;
        $xml =~ s/\>/\&gt\;/g;
        $xml =~ s/"/\&quot\;/g;
    }
    return $xml;
}

1;
