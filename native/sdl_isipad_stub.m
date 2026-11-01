#import <UIKit/UIKit.h>

/*
 * Provides SDL_IsIPad, which libSDL2.a references (from SDL_IsTablet in
 * SDL.c) but whose archive member (SDL_uikitvideo.o) does not define in our
 * Phase 2 build. Implemented exactly as upstream SDL 2.32.10 does in
 * src/video/uikit/SDL_uikitvideo.m: report the current device idiom.
 *
 * Linked into libSDL2.dylib by scripts/build-dylibs.sh; must stay a plain C
 * symbol (no prefix/suffix) so it satisfies the _SDL_IsIPad reference.
 */
int SDL_IsIPad(void)
{
	return ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) ? 1 : 0;
}
