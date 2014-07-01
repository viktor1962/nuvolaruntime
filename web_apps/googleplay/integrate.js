/*
 * Copyright 2011-2014 Jiří Janoušek <janousek.jiri@gmail.com>
 * Copyright 2014 Martin Pöhlmann <martin.deimos@gmx.de>
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met: 
 * 
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer. 
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution. 
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

(function(Nuvola)
{

var State = Nuvola.PlaybackState;
var PlayerAction = Nuvola.PlayerAction;
var player = Nuvola.$object(Nuvola.MediaPlayer);

var ACTION_THUMBS_UP = "thumbs-up";
var ACTION_THUMBS_DOWN = "thumbs-down";
var ACTION_RATING = "rating";
var STARS_ACTIONS = ["rating::0", "rating::1", "rating::2", "rating::3", "rating::4", "rating::5"]
var THUMBS_ACTIONS = ["thumbs-up", "thumbs-down"];

var WebApp = Nuvola.$WebApp();

WebApp.onInitAppRunner = function(emitter, values, entries)
{
	Nuvola.WebAppPrototype.onInitAppRunner.call(this, emitter, values, entries);
	
	Nuvola.Actions.addAction("playback", "win", "thumbs-up", "Thumbs up", null, null, null, true);
	Nuvola.Actions.addAction("playback", "win", "thumbs-down", "Thumbs down", null, null, null, true);
	var ratingOptions = [
		// Variant? parameter, string? label, string? mnemo_label, string? icon, string? keybinding
		[0, "Rating: 0 stars", null, null, null, null],
		[1, "Rating: 1 star", null, null, null, null],
		[2, "Rating: 2 stars", null, null, null, null],
		[3, "Rating: 3 stars", null, null, null, null],
		[4, "Rating: 4 stars", null, null, null, null],
		[5, "Rating: 5 stars", null, null, null, null]
	];
	Nuvola.Actions.addRadioAction("playback", "win", "rating", 0, ratingOptions);
}

WebApp.onInitWebWorker = function(emitter)
{
	Nuvola.WebAppPrototype.onInitWebWorker.call(this);
	
	Nuvola.Actions.connect("action-activated", this, "onActionActivated");
	this.thumbsUp = undefined;
	this.thumbsDown = undefined;
	this.starRating = undefined;
	this.starRatingEnabled = undefined;
	this.thumbRatingEnabled = undefined;
	document.addEventListener("DOMContentLoaded", this.onPageReady.bind(this));
}

WebApp.onPageReady = function(event)
{
	this.addNavigationButtons();
	this.update();
}

WebApp.update = function()
{
	var track = {};
	try
	{
		track.artLocation = document.getElementById('playingAlbumArt').src;
	}
	catch(e)
	{
		track.artLocation =  null;
	}
	
	try
	{
		var elm = document.getElementById('playerSongTitle').firstChild;
		track.title = elm.innerText || elm.textContent;
	}
	catch(e)
	{
		track.title = null;
	}
	
	try
	{
		var elm = document.getElementById('player-artist').firstChild;
		track.artist = elm.innerText || elm.textContent;
	}
	catch (e)
	{
		track.artist = null;
	}
	
	try
	{
		var elm = document.querySelector("#playerSongInfo .player-album");
		track.album = elm.innerText || elm.textContent;
	}
	catch (e)
	{
		track.album = null;
	}
	
	player.setTrack(track);
	
	var state = State.UNKNOWN;
	var prevSong, nextSong, canPlay, canPause;
	try
	{
		var buttons = document.querySelector("#player .player-middle");
		var pp = buttons.childNodes[2];
		if (pp.disabled === true)
			state = State.UNKNOWN;
		else if (pp.className == "flat-button playing")
			state = State.PLAYING;
		else
			state = State.PAUSED;
		
		if (state !== State.UNKNOWN)
		{
			prevSong = buttons.childNodes[1].disabled === false;
			nextSong = buttons.childNodes[3].disabled === false;
		}
		else
		{
			prevSong = nextSong = false;
		}
	}
	catch (e)
	{
		prevSong = nextSong = false;
	}
	
	player.setPlaybackState(state);
	player.setCanPause(state === State.PLAYING);
	player.setCanPlay(state === State.PAUSED);
	player.setCanGoPrev(prevSong);
	player.setCanGoNext(nextSong);
	
	// null = disabled; true/false toggled on/off
	var thumbsUp, thumbsDown;
	try
	{
		var thumbs = this.getThumbs();
		if (thumbs[0].style.visibility == "hidden")
		{
			thumbsUp = thumbsDown = null;
		}
		else
		{
			this.toggleThumbRating(true);
			thumbsUp = thumbs[1].className == "selected";
			thumbsDown = thumbs[2].className == "selected";
		}
	}
	catch (e)
	{
		thumbsUp = thumbsDown = null;
	}
	
	// null = disabled
	var starRating;
	try
	{
		var stars = this.getStars();
		if (stars.style.visibility == "hidden")
		{
			starRating = null;
		}
		else
		{
			this.toggleStarRating(true);
			starRating = stars.childNodes[0].getAttribute("data-rating") * 1;
		}
	}
	catch (e)
	{
		starRating = null;
	}
	
	if (this.thumbsUp !== thumbsUp)
	{
		this.thumbsUp = thumbsUp;
		Nuvola.Actions.setEnabled(ACTION_THUMBS_UP, thumbsUp !== null);
		Nuvola.Actions.setState(ACTION_THUMBS_UP, thumbsUp === true);
	}
	
	if (this.thumbsDown !== thumbsDown)
	{
		this.thumbsDown = thumbsDown;
		Nuvola.Actions.setEnabled(ACTION_THUMBS_DOWN, thumbsDown !== null);
		Nuvola.Actions.setState(ACTION_THUMBS_DOWN, thumbsDown === true);
	}
	
	if (this.starRating !== starRating)
	{
		this.starRating = starRating;
		var enabled = starRating !== null;
		Nuvola.Actions.setEnabled(ACTION_RATING, enabled);
		
		if (enabled)
			Nuvola.Actions.setState(ACTION_RATING, starRating);
	}
	
	setTimeout(this.update.bind(this), 500);
}

WebApp.getPlayerButtons = function()
{
	var elm = document.querySelector("#player .player-middle");
	return elm ? elm.childNodes : null;
}

WebApp.onActionActivated = function(object, name, param)
{
	var buttons = this.getPlayerButtons();
	if (buttons)
	{
		var prev_song = buttons[1];
		var next_song = buttons[3];
		var play_pause = buttons[2];
	}
	else
	{
		var prev_song = null;
		var next_song = null;
		var play_pause = null;
	}
	
	switch (name)
	{
	case PlayerAction.TOGGLE_PLAY:
		Nuvola.clickOnElement(play_pause);
		break;
	case PlayerAction.PLAY:
		if (player.state != State.PLAYING)
			Nuvola.clickOnElement(play_pause);
		break;
	case PlayerAction.PAUSE:
	case PlayerAction.STOP:
		if (player.state == State.PLAYING)
			Nuvola.clickOnElement(play_pause);
		break;
	case PlayerAction.PREV_SONG:
		if (prev_song)
			Nuvola.clickOnElement(prev_song);
		break;
	case PlayerAction.NEXT_SONG:
		if (next_song)
			Nuvola.clickOnElement(next_song);
		break;
	case ACTION_THUMBS_UP:
		Nuvola.clickOnElement(this.getThumbs()[1]);
		break;
	case ACTION_THUMBS_DOWN:
		Nuvola.clickOnElement(this.getThumbs()[2]);
		break;
	case ACTION_RATING:
		var stars = this.getStars().childNodes;
		var i = stars.length;
		while (i--)
		{
			var star = stars[i];
			if (star.getAttribute("data-rating") === ("" + param))
			{
				Nuvola.clickOnElement(star);
				break;
			}
		}
		break;
	}
}

WebApp.addNavigationButtons = function()
{
	/* Loading in progress? */
	var loading = document.getElementById("loading-progress");
	if (loading && loading.style.display != "none")
	{
		setTimeout(this.addNavigationButtons.bind(this), 250);
		return;
	}
	
	var queryBar = document.getElementById("gbq2");
	if (!queryBar)
	{
		console.log("Could not find the query bar.");
		return;
	}
	
	var queryBarFirstChild = queryBar.firstChild;
	
	var navigateBack = Nuvola.makeElement("button", null, "<");
	navigateBack.className = "button small vertical-align";
	navigateBack.style.float = "left";
	navigateBack.style.marginRight = "0px";
	navigateBack.style.borderTopRightRadius = "2px";
	navigateBack.style.borderBottomRightRadius = "2px";
	queryBar.insertBefore(navigateBack, queryBarFirstChild);
	
	var navigateForward = Nuvola.makeElement("button", null, ">");
	navigateForward.className = "button small vertical-align";
	navigateForward.style.float = "left";
	navigateForward.style.marginRight = "15px";
	navigateForward.style.borderLeft = "none";
	navigateForward.style.borderTopLeftRadius = "2px";
	navigateForward.style.borderLeftRightRadius = "2px";
	queryBar.insertBefore(navigateForward, queryBarFirstChild);
	
	Nuvola.Actions.attachButton(Nuvola.BrowserAction.GO_BACK, navigateBack);
	Nuvola.Actions.attachButton(Nuvola.BrowserAction.GO_FORWARD, navigateForward);
}

WebApp.getThumbs = function()
{
	var elm = document.querySelector("#player-right-wrapper .thumbs.rating-container");
	return [elm, elm.childNodes[0], elm.childNodes[1]];
}

WebApp.getStars = function()
{
	return document.querySelector("#player-right-wrapper .stars.rating-container");
}

WebApp.toggleStarRating = function(enabled)
{
	if (enabled && this.starRatingEnabled !== true)
	{
		Nuvola.Player.addExtraActions(STARS_ACTIONS);
		this.starRatingEnabled = true;
	}
}

WebApp.toggleThumbRating = function(enabled)
{
	if (enabled && this.thumbRatingEnabled !== true)
	{
		Nuvola.Player.addExtraActions(THUMBS_ACTIONS);
		this.thumbRatingEnabled = true;
	}
}

WebApp.start();

})(this);  // function(Nuvola)
