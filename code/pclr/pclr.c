/*****************************************************************************
 * pclr.c -- Make any program hard on the eyes ;)
 * Inspired by Darxus' program by the same name in Perl.
 * Visit his home page at http://www.ChaosReighs.com/
 * Usage:  <any command> |pclr
 * Compile this with a command like "gcc -o pclr pclr.c".
 *
 * Copyright (C) 2001, Bill Jonas <bill@billjonas.com>
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 *
 * Copies of the GNU General Public License may also be obtained
 * electronically at http://www.gnu.org/copyleft/gpl.html
 *****************************************************************************/
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <time.h>

int main (void)
{
    char end[] = "\E[00m"; /* Sequence that turns off all ANSI-ness */
    char ch;               /* The current character to be printed */
    char skip, next;       /* We don't want to try to colorize ANSI/VT100
			      escape sequences; more in a bit. */

    srand (time (NULL));

    while ((ch = getchar()) != EOF) {
        if (ch == '\E') {
            skip = 1; /* Start skipping if it's an escape char */
        }
        if (skip && isalpha(ch)) {
            next = 1;  /* Escape sequences end with an alphabetic
				      character.  We'll start colorizing at the
				      next go-round. */
        }
        if (!skip) {  /* Why rand like below?  See rand(3) on a Linux system
		         Basically, we want to use the high-order bits instead
		         of the low-order bits. */
            printf("\E[0%d;%dm",(int)(2.0*rand()/RAND_MAX),
                    (int)(7.0*rand()/RAND_MAX+31.0));
        }
        printf("%c",ch);
        if (next) {
            skip = next = 0;  /* Reset so we can colorize the next
					     printing character. */
        }
        fflush(stdout);
    }
    printf("%s",end);
    return 0;
}
