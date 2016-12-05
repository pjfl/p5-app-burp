requires "Class::Usul" => "v0.78.0";
requires "Daemon::Control" => "0.001006";
requires "Data::Validation" => "v0.27.0";
requires "File::ChangeNotify" => "0.26";
requires "File::DataClass" => "v0.71.0";
requires "Moo" => "2.001001";
requires "Unexpected" => "v0.45.0";
requires "namespace::autoclean" => "0.26";
requires "perl" => "5.010001";
requires "strictures" => "2.000000";

on 'build' => sub {
  requires "Module::Build" => "0.4004";
  requires "version" => "0.88";
};

on 'test' => sub {
  requires "File::Spec" => "0";
  requires "Module::Build" => "0.4004";
  requires "Module::Metadata" => "0";
  requires "Sys::Hostname" => "0";
  requires "Test::Requires" => "0.06";
  requires "version" => "0.88";
};

on 'test' => sub {
  recommends "CPAN::Meta" => "2.120900";
};

on 'configure' => sub {
  requires "Module::Build" => "0.4004";
  requires "version" => "0.88";
};
