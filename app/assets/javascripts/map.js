$(document).ready(function(){
	if ($('#venues').length > 0) {
		function GMapsInitialize() {
			var geocoder = new google.maps.Geocoder();
	        var mapOptions = {
	          center: new google.maps.LatLng(37.797295, -122.412500),
	          zoom: 13
	        };
	        var map = new google.maps.Map(document.getElementById("map"), mapOptions);

		    var addresses = $('span.addressOnMap');
		    for (var i = 0 ; i < addresses.length; i++) {
		    	var address = $(addresses[i]).html();
		    	geocoder.geocode( { 'address': address }, function(results, status) {
					if (status == google.maps.GeocoderStatus.OK) {
						var marker = new google.maps.Marker({
							map: map,
							position: results[0].geometry.location
						});
						var infowindow = new google.maps.InfoWindow({ content: results[0].formatted_address });
						google.maps.event.addListener(marker, 'click', function() {
							infowindow.open(map,marker);
						});
					} else {
						/* Do nothing */
					}
				});
		    }
	    }
	    google.maps.event.addDomListener(window, 'load', GMapsInitialize);
	}
});