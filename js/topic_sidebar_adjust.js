function resized(){
	var nav = document.querySelector('body.with_sidebar main nav');
	if( nav ) {
		var rect = nav.getBoundingClientRect();
		if( rect.left < 200 )
			nav.className = "below";
		else
			nav.className = "";
	}
}

window.addEventListener("load", resized, false);
window.addEventListener("resize", resized, false);
