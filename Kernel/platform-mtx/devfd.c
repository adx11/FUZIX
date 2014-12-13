#include <kernel.h>
#include <kdata.h>
#include <printf.h>
#include <devfd.h>

/* Two drives but minors 2,3 are single density mode */
#define MAX_FD	4

#define OPDIR_NONE	0
#define OPDIR_READ	1
#define OPDIR_WRITE	2

#define FD_READ		0x88	/* 2797 needs 0x88, 1797 needs 0x80 */
#define FD_WRITE	0xA8	/* Likewise A8 v A0 */

static uint8_t motorct;
static uint8_t fd_selected = 0xFF;
static uint8_t fd_tab[MAX_FD];

/*
 *	We only support normal block I/O
 */

static int fd_transfer(uint8_t minor, bool is_read, uint8_t rawflag)
{
    blkno_t block;
    uint16_t dptr;
    int ct = 0;
    int tries;
    uint8_t err = 0;
    uint8_t *driveptr = fd_tab + minor;
    uint8_t cmd[6];

    if(rawflag)
        goto bad2;

    if (fd_selected != minor) {
        uint8_t err = fd_motor_on(minor|(minor > 1 ? 0: 0x10));
        if (err)
            goto bad;
    }

    dptr = (uint16_t)udata.u_buf->bf_data;
    block = udata.u_buf->bf_blk;

//    kprintf("Issue command: drive %d\n", minor);
    cmd[0] = is_read ? FD_READ : FD_WRITE;
    cmd[1] = block / 8;		/* 2 sectors per block */
    cmd[2] = ((block & 7) << 1) + 1;
    cmd[3] = is_read ? OPDIR_READ: OPDIR_WRITE;
    cmd[4] = dptr & 0xFF;
    cmd[5] = dptr >> 8;

    while (ct < 2) {
        for (tries = 0; tries < 4 ; tries++) {
            err = fd_operation(cmd, driveptr);
            if (err == 0)
                break;
            if (tries > 1)
                fd_reset(driveptr);
        }
        /* FIXME: should we try the other half and then bale out ? */
        if (tries == 3)
            goto bad;
        cmd[5]++;
        cmd[2]++;	/* Next sector for next block */
        ct++;
    }
    return 1;
bad:
    kprintf("fd%d: error %x\n", minor, err);
bad2:
    udata.u_error = EIO;
    return -1;
}

int fd_open(uint8_t minor, uint16_t flag)
{
    flag;
    if(minor >= MAX_FD) {
        udata.u_error = ENODEV;
        return -1;
    }
    return 0;
}

int fd_read(uint8_t minor, uint8_t rawflag, uint8_t flag)
{
    flag;
    return fd_transfer(minor, true, rawflag);
}

int fd_write(uint8_t minor, uint8_t rawflag, uint8_t flag)
{
    flag;
    return fd_transfer(minor, false, rawflag);
}