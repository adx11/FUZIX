#ifndef __DEVHD_DOT_H__
#define __DEVHD_DOT_H__

/* public interface */
int hd_read(uint8_t minor, uint8_t rawflag, uint8_t flag);
int hd_write(uint8_t minor, uint8_t rawflag, uint8_t flag);
int hd_open(uint8_t minor, uint16_t flag);

/* helpers in common memory for the block transfers */
int hd_xfer_in(uint16_t addr);
int hd_xfer_out(uint16_t addr);

void hd_probe(void);

#endif /* __DEVHD_DOT_H__ */
