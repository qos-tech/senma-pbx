jQuery.noConflict();
jQuery(function() {

	//side menu toggle (init)
	if (isIE() <= 9) {
		jQuery('#sidebar').find("li.active").has("ul").children("ul").collapse("show");
		jQuery('#sidebar').find("li").not(".active").has("ul").children("ul").collapse("hide");
	} else {
		jQuery('#sidebar').find("li.active").has("ul").children("ul").addClass("collapse in");
		jQuery('#sidebar').find("li").not(".active").has("ul").children("ul").addClass("collapse");
	}

	//side menu toggle (setting)
	jQuery("#sidebar-area .dropdown-collapse").on((jQuery.support.touch ? "tap" : "click"), function(e) {
		e.preventDefault();

		if (jQuery("body").hasClass("sidebar-closed")) {
			return false;
		}

		jQuery(this).parent("li").toggleClass("active").children("ul").collapse("toggle");

		//if (jQuerytoggle) { //toggle On ・ Off

		jQuery(this).parent("li").siblings().removeClass("active").children("ul.in").collapse("hide");

		//}
		return false;
	});

	handleSidebarToggler();
});

//Loads the correct sidebar on window load,
//collapses the sidebar on window resize.
// Sets the min-height of #page-wrapper to window size
jQuery(function() {
	var width = (window.innerWidth > 0) ? window.innerWidth : screen.width;

	if (jQuery.cookie && jQuery.cookie('sidebar-closed') === '1' && !jQuery('body').hasClass("sidebar-closed") && width >= 768) {
		jQuery('body').addClass("sidebar-closed");
		jQuery('#sidebar .nav-second-level, #sidebar .nav-third-level').removeClass('collapse');
	}

	jQuery(window).bind("load resize", function() {
		topOffset = 50;
		var body = jQuery('body');
		var sidebarMenuSubs = jQuery('#sidebar .nav-second-level, #sidebar .nav-third-level');

		width = (this.window.innerWidth > 0) ? this.window.innerWidth : this.screen.width;

		if (width < 768) {
			jQuery('div.navbar-collapse').addClass('collapse');
			topOffset = 100; // 2-row-menu

			if (body.hasClass("sidebar-closed")) {
				body.removeClass("sidebar-closed");
				sidebarMenuSubs.addClass('collapse');
			}
		} else {
			jQuery('div.navbar-collapse').removeClass('collapse');
			/*
			if (jQuery.cookie) {
				if (jQuery.cookie('sidebar-closed') === 1 && !jQuery('body').hasClass("sidebar-closed")) {
					body.addClass("sidebar-closed");
					sidebarMenuSubs.removeClass('collapse');
				}
			}*/
		}

		height = ((this.window.innerHeight > 0) ? this.window.innerHeight : this.screen.height) - 1;
		height = height - topOffset;
		if (height < 1) height = 1;
		if (height > topOffset) {
			jQuery("#page-wrapper").css("min-height", (height) + "px");
		}
	});

	var url = window.location;
	var element = jQuery('ul.nav a').filter(function() {
		return this.href == url;
	}).addClass('active').parent().parent().addClass('in').parent();
	if (element.is('li')) {
		element.addClass('active');
	}

	if (jQuery('#pageLoading').css("display") == "block") {
		jQuery('#pageLoading').delay(100).css("display","none");
	}

});

//Top Toggler
var handleSidebarToggler = function () {
	var body = jQuery('body');

	// handle sidebar show/hide
	body.on('click', '.sidebar-toggler', function (e) {

		var sidebarMenuSubs = jQuery('#sidebar .nav-second-level, #sidebar .nav-third-level');

		//collapse("toggle")
		jQuery("#sidebar-area .dropdown-collapse").parent("li").children("ul").css('height', '');

		jQuery(".sidebar-search", jQuery('.page-sidebar')).removeClass("open");
		if (body.hasClass("sidebar-closed")) {
			body.removeClass("sidebar-closed");
			sidebarMenuSubs.addClass('collapse');

			if (jQuery.cookie) {
				jQuery.cookie('sidebar-closed', '0');
			}
		} else {
			body.addClass("sidebar-closed");
			sidebarMenuSubs.removeClass('collapse');

			if (jQuery.cookie) {
				jQuery.cookie('sidebar-closed', '1');
			}
		}
		jQuery(window).trigger('resize');
	});
};

//IE Checker
var isIE = function() {
	var undef,
		v = 3,
		div = document.createElement("div"),
		all = div.getElementsByTagName("i");
	while (
		div.innerHTML = "<!--[if gt IE " + (++v) + "]><i></i><![endif]-->",
		all[0]
	) {
		return v > 4 ? v : undef;
	}
}

jQuery(function() {
	jQuery(document).ready(function () {
	    var menu    = jQuery('#sidebarmenu').height()
	    var content = jQuery(document).height();

	    if (menu > content) {
	        jQuery('.sidebar').height(menu)
	    } else {
	        jQuery('#sidebarmenu').height(content-50);
	    }
	});
});
