package App::Burp::Watcher;

use namespace::autoclean;

use App::Burp; our $VERSION = $App::Burp::VERSION;

use Class::Usul::Constants qw( EXCEPTION_CLASS FALSE NUL OK SPC TRUE );
use Class::Usul::Functions qw( get_user is_hashref io throw );
use Class::Usul::Types     qw( ArrayRef HashRef NonEmptySimpleStr
                               Object PositiveInt RegexpRef );
use Daemon::Control;
use English                qw( -no_match_vars );
use File::ChangeNotify;
use File::DataClass::Types qw( Path );
use Scalar::Util           qw( blessed );
use Try::Tiny;
use Unexpected::Functions  qw( Unspecified );
use Moo;

extends q(Class::Usul::Programs);

# Private methods
my $_run_cmd = sub {
   my ($self, $mtimes, $opts, $event) = @_;

   my $path  = io io( $event->path )->canonpath;
   my $file  = $path->basename; $file =~ $self->config->exclude and return;
   my $mtime = $path->stat->{mtime};

   exists $mtimes->{ "${path}" } and $mtimes->{ "${path}" } == $mtime
      and return;

   $mtimes->{ "${path}" } = $mtime;

   try {
      my $tuples = $self->commands->{ $path->dirname }
         or throw 'Directory [_1] has no commands', [ $path->dirname ];

      for my $tuple (grep { $file =~ $_->[ 0 ] } @{ $tuples }) {
         if (is_hashref $tuple->[ 1 ]) { $self->run_cmd( $tuple->[ 1 ] ) }
         else { $self->run_cmd( $tuple->[ 1 ], $opts ) }

         last;
      }
   }
   catch { $self->log->error( $_ ) };

   return;
};

my $_daemon = sub {
   my $self = shift;

   $PROGRAM_NAME = $self->_program_name.SPC.io( '.' )->parent->basename;

   $self->config->appclass->env_var( 'debug', $self->debug );

   my $mtimes = {}; my $cmd_opts = { out => 'stdout', err => 'stderr' };

   while (my @events = $self->watcher->wait_for_events) {
      for my $event (@events) { $self->$_run_cmd( $mtimes, $cmd_opts, $event ) }
   }

   exit OK;
};

# Attribute constructors
my $_build_commands = sub {
   my $self = shift; my $watchers = $self->config->watchers; my $cmds = {};

   for my $path (keys %{ $watchers }) {
      my $io = io $path; my $file = $io->basename;

      my $pattern = qr{ \A $file \z }mx;

      push @{ $cmds->{ $io->dirname } }, [ $pattern, $watchers->{ $path } ];
   }

   return $cmds;
};

my $_build_directories = sub {
   my $self = shift;
   my $watchers = $self->config->watchers;
   my $dirs = { map { io( $_ )->dirname => TRUE } keys %{ $watchers } };

   return [ sort keys %{ $dirs } ];
};

my $_build_filter = sub {
   my $self = shift;
   my $watchers = $self->config->watchers;
   my $files = { map { io( $_ )->basename => TRUE } keys %{ $watchers } };
   my $pattern = join '|', keys %{ $files };

   return qr{ \A (?: $pattern ) \z }mx;
};

my $_build_watcher = sub {
   return File::ChangeNotify->instantiate_watcher
      ( directories => $_[ 0 ]->directories, filter => $_[ 0 ]->filter );
};

my $_stdio_file = sub {
   my ($self, $extn, $name) = @_; $name //= $self->_program_name;

   return $self->file->tempdir->catfile( "${name}.${extn}" );
};

my $_build_daemon_control = sub {
   my $self = shift; my $conf = $self->config;

   my $prog = $conf->binsdir->catfile( $self->_program_name );
   my $args = {
      name         => $conf->appclass,
      path         => $prog->pathname,

      directory    => $conf->appldir,
      program      => sub { shift; $self->$_daemon( @_ ) },
      program_args => [],

      pid_file     => $self->_pid_file->pathname,
      stderr_file  => $self->$_stdio_file( 'err' ),
      stdout_file  => $self->$_stdio_file( 'out' ),

      fork         => 2,
   };

   return Daemon::Control->new( $args );
};

# Public attributes
# Override default in base class
has '+config_class' => default => 'App::Burp::Config';

has 'commands' => is => 'lazy',
   isa => HashRef[ArrayRef|HashRef|NonEmptySimpleStr],
   builder => $_build_commands;

has 'directories' => is => 'lazy', isa => ArrayRef[NonEmptySimpleStr],
   builder => $_build_directories;

has 'filter' => is => 'lazy', isa => RegexpRef, builder => $_build_filter;

has 'watcher' => is => 'lazy', isa => Object, builder => $_build_watcher;

# Private attributes
has '_daemon_control' => is => 'lazy', isa => Object,
   builder => $_build_daemon_control;

has '_pid_file' => is => 'lazy', isa => Path, builder => sub {
   my $file = $_[ 0 ]->config->name.'.pid';

   return $_[ 0 ]->config->rundir->catfile( $file )->chomp
   };

has '_program_name' => is => 'lazy', isa => NonEmptySimpleStr,
   builder => sub { $_[ 0 ]->config->name };

# Construction
around 'run' => sub {
   my ($orig, $self) = @_; my $daemon = $self->_daemon_control;

   $daemon->name or throw Unspecified, [ 'name' ];

   $daemon->uid and not $daemon->gid
                and $daemon->gid( get_user( $daemon->uid )->gid );

   $self->quiet( TRUE );

   return $orig->( $self );
};

# Public methods
sub dump_self : method {
   my $self = shift; $self->directories; $self->filter; $self->commands;

   return $self->SUPER::dump_self;
}

sub is_running {
   return $_[ 0 ]->_daemon_control->pid_running ? TRUE : FALSE;
}

sub restart : method {
   my $self = shift; $self->params->{restart} = [ { expected_rv => 1 } ];

   $self->is_running and $self->stop;

   return $self->start;
}

sub show_warnings : method {
   $_[ 0 ]->_daemon_control->do_show_warnings; return OK;
}

sub start : method {
   my $self = shift; $self->params->{start} = [ { expected_rv => 1 } ];

   $self->is_running and throw 'Already running';

   return $self->_daemon_control->do_start;
}

sub status : method {
   my $self = shift; $self->params->{status} = [ { expected_rv => 3 } ];

   return $self->_daemon_control->do_status;
}

sub stop : method {
   my $self = shift; $self->params->{stop} = [ { expected_rv => 1 } ];

   $self->is_running or throw 'Not running';

   return $self->_daemon_control->do_stop;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Burp::Watcher - Watches for changes in files and runs commands

=head1 Synopsis

   use App::Burp::Watcher;
   # Brief but working code examples

=head1 Description

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=back

=head1 Subroutines/Methods

=head2 C<restart> - Restart the server

Restart the server

=head2 C<show_warnings> - Show server warnings

Show server warnings

=head2 C<start> - Start the server

Start the server

=head2 C<status> - Show the current server status

Show the current server status

=head2 C<stop> - Stop the server

Stop the server

=head1 Diagnostics

=head1 Dependencies

=over 3

=item L<Class::Usul>

=back

=head1 Incompatibilities

There are no known incompatibilities in this module

=head1 Bugs and Limitations

There are no known bugs in this module. Please report problems to
http://rt.cpan.org/NoAuth/Bugs.html?Dist=App-Burp.
Patches are welcome

=head1 Acknowledgements

Larry Wall - For the Perl programming language

=head1 Author

Peter Flanigan, C<< <pjfl@cpan.org> >>

=head1 License and Copyright

Copyright (c) 2016 Peter Flanigan. All rights reserved

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself. See L<perlartistic>

This program is distributed in the hope that it will be useful,
but WITHOUT WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE

=cut

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
