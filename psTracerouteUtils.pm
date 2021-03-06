#!/usr/bin/perl
#======================================================================
#
#       psTracerouteUtils.pm
#
#       Helper Utilities for viewing traceroute data stored in PerfSonar.
#	Version 2, with support for esmond
#
#       Written by: Dale W. Carder, dwcarder@wisc.edu
#       Network Services Group
#       Division of Information Technology
#       University of Wisconsin at Madison
#
#       Inspired in large part by traceroute_improved.cgi by Yuan Cao <caoyuan@umich.edu>
#
#       Copyright 2014 The University of Wisconsin Board of Regents
#       Licensed and distributed under the terms of the Artistic License 2.0
#
#       See the file LICENSE for details or reference the URL:
#        http://www.perlfoundation.org/artistic_license_2_0
#
#======================================================================

package psTracerouteUtils;


#=====================================================
#    U S E  A N D  R E Q U I R E
#=====================================================
use warnings;
use strict;
use lib '/usr/lib/perfsonar/lib';
use Exporter;                           # easy perl module functions
use Data::Dumper;
use Data::Validate::IP qw(is_ipv4 is_ipv6);
use perfSONAR_PS::Client::Esmond::ApiConnect;


#=====================================================
#   E X P O R T
#=====================================================
use vars qw(@ISA @EXPORT);              # perl module variables
our $VERSION = 2.0;		# 2.0 adds esmond support
@ISA = qw(Exporter);
@EXPORT = qw( GetTracerouteMetadata GetTracerouteData DeduplicateTracerouteData );


#=====================================================
#    P R O T O T Y P E S
#=====================================================
sub GetTracerouteData($$$$$);
sub GetTracerouteMetadata($$$$);
sub GetTracerouteMetadataFromESmond($$$$);
sub GetTracerouteDataFromEsmond($$$$$);
sub DeduplicateTracerouteData($$);



#==============================================================================
#            B E G I N   S U B R O U T I N E S 



#===============================================================================
#                       GetTracerouteMetadata
#
#	wrapper to go get available traceroute metadata from esmond or old MA
#
#  Arguments:
#     arg[0]: full url to use
#     arg[1]: start time to query (unix time)
#     arg[2]: end time to query (unix time)
#     arg[3]: hashref to fill with metadata
#
sub GetTracerouteMetadata($$$$) {
	my $url = shift;
	my $stime = shift;
	my $etime = shift;
	my $endpoint = shift;
    
    #Currently only one type of MA, but could select from multiple in future
	return(GetTracerouteMetadataFromESmond($url,$stime,$etime,$endpoint));
}


#===============================================================================
#                       GetTracerouteData
#
#	wrapper to go get available traceroute data from esmond or old MA
#
#  Arguments:
#     arg[0]: full url of the of the traceroute data source
#     arg[1]: either metadata key or URI of the of the traceroute data source
#     arg[2]: start time to query (unix time)
#     arg[3]: end time to query (unix time)
#     arg[4]: hashref to fill with data
#
sub GetTracerouteData($$$$$) {
	my $url = shift;
	my $ma = shift;
	my $stime = shift;
	my $etime = shift;
	my $topology = shift;
    
    #Currently only one type of MA, but could select from multiple in future
	return(GetTracerouteDataFromEsmond($url,$ma,$stime,$etime,$topology));
}

#===============================================================================
#                       GetTracerouteMetadataFromEsmond
#
#  Arguments:
#     arg[0]: full url of the archive
#     arg[1]: start time to query (unix time)
#     arg[2]: end time to query (unix time)
#     arg[3]: a hash reference to fill with endpoint information
#
#	Returns error message, if there is one.
#
sub GetTracerouteMetadataFromESmond($$$$) {

	my $url = shift;    
	my $start_time = shift;
	my $end_time = shift;
	my $endpoint = shift;
	
	my $filters = new perfSONAR_PS::Client::Esmond::ApiFilters();
    $filters->metadata_filters->{'event-type'} = 'packet-trace';
	$filters->time_start($start_time);
	# note: time_end does not actually work with metadata, see 
	# https://code.google.com/p/perfsonar-ps/wiki/MeasurementArchivePerlAPI#Advanced_Time_Filter_Usage

	my $client = new perfSONAR_PS::Client::Esmond::ApiConnect(
	    url => $url,
	    filters => $filters
	);
	
	my $md = $client->get_metadata();
	
	if ($client->error) {
		return($client->error);
	}
	
	# iterate through results
	my $key;
	foreach my $m(@{$md}){

		#my $id = $m->get_field('metadata-key');
		my $id = $m->get_event_type("packet-trace")->base_uri();

		$$endpoint{$id}{'srcval'} = $m->get_field('source');
		$$endpoint{$id}{'dstval'} = $m->get_field('destination');

		# some backwards compatibility with the old xml MA here,
		# results in helping the UI out later
		if (is_ipv4($m->get_field('source'))) {
			$$endpoint{$id}{'srctype'} = 'ipv4';
		} elsif (is_ipv6($m->get_field('source'))) {
			$$endpoint{$id}{'srctype'} = 'ipv6';
		}

		if (is_ipv4($m->get_field('destination'))) {
			$$endpoint{$id}{'dsttype'} = 'ipv4';
		} elsif (is_ipv6($m->get_field('destination'))) {
			$$endpoint{$id}{'dsttype'} = 'ipv6';
		}
	}

} # end GetTracerouteMetadataFromEsmond



#===============================================================================
#                       GetTracerouteDataFromEsmond
#
#  Arguments:
#     arg[0]: host url of measurement archive
#     arg[1]: uri of specific measurement
#     arg[1]: start time to query (unix time)
#     arg[2]: end time to query (unix time)
#     arg[3]: hashref to fill with results:
#		$hashref{unix_timestamp}{hop #}{ip addr} = mtu
#	
#  Returns:
#	error message (if any)
#
sub GetTracerouteDataFromEsmond($$$$$) {

    my $url = shift;    
    my $uri = shift;    
    my $start_time = shift;
    my $end_time = shift;
	my $results = shift;

	my $filter = new perfSONAR_PS::Client::Esmond::ApiFilters();
	$filter->time_start($start_time);
	$filter->time_end($end_time);

	my $result_client = new perfSONAR_PS::Client::Esmond::ApiConnect(
	    url => $url,
	    filters => $filter
	);
	
	my $data = $result_client->get_data($uri); # the uri from previous phase
	if($result_client->error) {
		return($result_client->error);
	}

		# for each datapoint
	    foreach my $d (@{$data}){
	        #print "Time: " . $d->datetime . "\n";
	        foreach my $hop (@{$d->val}){
	            #print "ttl=" . $hop->{ttl} . ",query=" . $hop->{query};
	            if($hop->{success}){
	                #print ",ip=" . $hop->{ip} . ",rtt=" . $hop->{rtt} . ",mtu=" . $hop->{mtu} . "\n";

					$$results{$d->ts}{$hop->{ttl}}{$hop->{ip}} = {
					    'mtu' => $hop->{mtu},
					    'rtt' =>  $hop->{rtt},
					};
	            }else{
					if (defined($hop->{error_message})) {
						$$results{$d->ts}{$hop->{ttl}}{$hop->{error_message}} = 1;
					} else {
						$$results{$d->ts}{$hop->{ttl}}{'error'} = 1;
					}
	            }
	        }
	    }
	return('');
}



#===============================================================================
#                       DeduplicateTracerouteData
#
#  Arguments:
#     arg[0]: hash ref datastructure containing data to parse
#     arg[1]: hash ref datastructure to fill
#
#  Returns: 
#
#
sub DeduplicateTracerouteData($$) {
	my $current_topology = shift;
	my $new_topology = shift;

	my %last_topology;

	foreach my $timestamp (sort keys(%{$current_topology})) {

		my $topologychange=0;

		#print "\n\n\n new time: $timestamp\n";
		# see if this is the 1st run
		if (scalar(keys(%last_topology)) < 1) {
			#print "this is the 1st run\n";
			%last_topology = %{$$current_topology{$timestamp}};
			$topologychange=1;

		# or, let's compare topologies
		} else {

			#print "current: -------------\n";
			#print Dumper($$current_topology{$timestamp});
			#print "last: -------------\n";
			#print Dumper(\%last_topology);

		   TOPOCOMPARE1:
		   foreach my $hop (keys(%last_topology)) {

				# see if the old toplology has something the new one doen't have
				foreach my $rtr ( keys(%{$last_topology{$hop}}) ) {
					if (! defined($$current_topology{$timestamp}{$hop}{$rtr})) {
						$topologychange=1;
						#print "topo change1 at $timestamp for $rtr\n";
						last TOPOCOMPARE1;
					}
				}
		   }

		   if ($topologychange eq 0) {
		   		TOPOCOMPARE2:
				foreach my $hop (keys(%{$$current_topology{$timestamp}})) {
		   	 		# see if the new toplology has something the old one doen't have
				   	foreach my $rtr ( keys(%{$$current_topology{$timestamp}{$hop}}) ) {
		   	 			if (! defined($last_topology{$hop}{$rtr})) {
		   	 				$topologychange=1;
		   	 				#print "topo change2 at $timestamp for $rtr\n";
		   	 				last TOPOCOMPARE2;
		   	 			}
		   	 		}
		   	  	}
		   	}
		} #done comparting topologies

		if ($topologychange) {
			#print "topology change at $timestamp\n";
			# save this topology at this timestamp
			$$new_topology{$timestamp} = $$current_topology{$timestamp};
			%last_topology = %{$$current_topology{$timestamp}};
		} else {
			#print "NO topology changes found at $timestamp\n";
		}
	
	} # end for each timestamp row

	return;

} # end DeduplicateTracerouteData

1;
