#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <dlfcn.h>
#import "ESPRenderer.h"

#define RVA_GET_INSTANCE       0x3F2F90C
#define OFF_GUID               0xA8
#define OFF_ID                 0xAC
#define OFF_LEVEL              0xB4
#define OFF_HP                 0xC8
#define OFF_HP_MAX             0xCC
#define OFF_IS_SELF            0x1B0
#define OFF_IS_DEAD            0x1D0
#define OFF_CAMP               0x1DC
#define OFF_IS_PLAYER          0x5C
#define OFF_POS_CACHE          0x294

#define SHOW_IS_PLAYER         0x93
#define SHOW_IS_DEAD           0xCD
#define SHOW_CAMP              0xD8
#define SHOW_GUID              0x190
#define SHOW_LEVEL             0x198
#define SHOW_HP                0x1AC
#define SHOW_HP_MAX            0x1B0
#define SHOW_IS_SELF           0x250
#define SHOW_POS_CACHE         0x294

#define IL2CPP_LIST_ITEMS      0x10
#define IL2CPP_LIST_SIZE       0x18
#define IL2CPP_ARRAY_DATA      0x20

static uintptr_t g_base = 0;

static uintptr_t getBase(void) {
    if (g_base) return g_base;
    
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        
        const char *lastSlash = strrchr(name, '/');
        if (!lastSlash) continue;
        
        const char *binary = lastSlash + 1;
        if (strcmp(binary, "legends") == 0) {
            const struct mach_header *header = _dyld_get_image_header(i);
            if (header && header->magic == MH_MAGIC_64) {
                g_base = (uintptr_t)header;
                return g_base;
            }
        }
    }
    
    return 0;
}

static bool safeRead(uintptr_t addr, void *buffer, size_t size) {
    if (addr == 0) return false;
    if (addr < 0x100000000) return false;
    if (addr > 0x80000000000) return false;
    
    vm_size_t bytesRead = 0;
    kern_return_t kr = vm_read_overwrite(
        mach_task_self(),
        (vm_address_t)addr,
        size,
        (vm_address_t)buffer,
        &bytesRead
    );
    return (kr == KERN_SUCCESS && bytesRead >= size);
}

static uint32_t readU32(uintptr_t addr) {
    uint32_t v = 0;
    if (!safeRead(addr, &v, 4)) return 0;
    return v;
}

static uint64_t readU64(uintptr_t addr) {
    uint64_t v = 0;
    if (!safeRead(addr, &v, 8)) return 0;
    return v;
}

static float readFloat(uintptr_t addr) {
    float v = 0;
    if (!safeRead(addr, &v, 4)) return 0;
    return v;
}

static bool readBool(uintptr_t addr) {
    uint8_t v = 0;
    if (!safeRead(addr, &v, 1)) return false;
    return v != 0;
}

static int32_t readI32(uintptr_t addr) {
    int32_t v = 0;
    if (!safeRead(addr, &v, 4)) return 0;
    return v;
}

static uintptr_t getGameMapSafe(void) {
    uintptr_t base = getBase();
    if (!base) return 0;
    
    uint8_t code[16];
    uintptr_t methodAddr = base + RVA_GET_INSTANCE;
    
    if (!safeRead(methodAddr, code, 16)) return 0;
    
    uint32_t instr1 = (uint32_t)code[0] | ((uint32_t)code[1] << 8) 
                    | ((uint32_t)code[2] << 16) | ((uint32_t)code[3] << 24);
    uint32_t instr2 = (uint32_t)code[4] | ((uint32_t)code[5] << 8) 
                    | ((uint32_t)code[6] << 16) | ((uint32_t)code[7] << 24);
    
    if ((instr1 & 0x9F000000) != 0x90000000) return 0;
    
    uint32_t rd = instr1 & 0x1F;
    uint32_t immlo = (instr1 >> 29) & 0x3;
    uint32_t immhi = (instr1 >> 5) & 0x7FFFF;
    int32_t imm = (int32_t)((immhi << 2) | immlo);
    if (imm & 0x1000000) imm |= 0xFE000000;
    
    int64_t pageOffset = (int64_t)imm << 12;
    
    uintptr_t pc = methodAddr;
    uintptr_t page = (pc & ~0xFFFULL) + (uintptr_t)pageOffset;
    
    if ((instr2 & 0xFFC00000) != 0xF9400000) return 0;
    
    uint32_t ldrRn = (instr2 >> 5) & 0x1F;
    uint32_t imm12 = (instr2 >> 10) & 0xFFF;
    uintptr_t offset = (uintptr_t)imm12 * 8;
    
    if (rd != ldrRn) return 0;
    
    uintptr_t staticAddr = page + offset;
    
    uintptr_t instance = readU64(staticAddr);
    
    if (instance > 0x100000000 && instance < 0x80000000000) {
        return instance;
    }
    
    return 0;
}

static bool isValidEntity(uintptr_t ptr) {
    if (ptr < 0x100000000 || ptr > 0x80000000000) return false;
    if (ptr == 0) return false;
    
    uint8_t isPlayer = 0;
    if (!safeRead(ptr + OFF_IS_PLAYER, &isPlayer, 1)) return false;
    if (isPlayer != 1) return false;
    
    uint64_t guid = 0;
    if (!safeRead(ptr + OFF_GUID, &guid, 8)) return false;
    if (guid == 0) return false;
    
    int32_t hpMax = 0;
    safeRead(ptr + OFF_HP_MAX, &hpMax, 4);
    if (hpMax < 0 || hpMax > 100000) return false;
    
    int32_t camp = 0;
    safeRead(ptr + OFF_CAMP, &camp, 4);
    if (camp < 0 || camp > 3) return false;
    
    return true;
}

static bool isValidShowEntity(uintptr_t ptr) {
    if (ptr < 0x100000000 || ptr > 0x80000000000) return false;
    if (ptr == 0) return false;
    
    uint8_t isPlayer = 0;
    if (!safeRead(ptr + SHOW_IS_PLAYER, &isPlayer, 1)) return false;
    if (isPlayer != 1) return false;
    
    uint64_t guid = 0;
    if (!safeRead(ptr + SHOW_GUID, &guid, 8)) return false;
    if (guid == 0) return false;
    
    int32_t hpMax = 0;
    safeRead(ptr + SHOW_HP_MAX, &hpMax, 4);
    if (hpMax < 0 || hpMax > 100000) return false;
    
    return true;
}

int parseEntities(ESPEntity *out, int maxCount) {
    if (!out || maxCount <= 0) return 0;
    
    uintptr_t gameMap = getGameMapSafe();
    if (!gameMap) return 0;
    
    int count = 0;
    
    for (uintptr_t offset = 0x10; offset < 0x200 && count < maxCount; offset += 8) {
        uintptr_t fieldPtr = readU64(gameMap + offset);
        if (fieldPtr < 0x100000000 || fieldPtr > 0x80000000000) continue;
        
        uintptr_t itemsPtr = readU64(fieldPtr + IL2CPP_LIST_ITEMS);
        if (itemsPtr < 0x100000000 || itemsPtr > 0x80000000000) continue;
        
        int32_t size = readI32(fieldPtr + IL2CPP_LIST_SIZE);
        if (size < 0 || size > 20) continue;
        
        for (int i = 0; i < size && count < maxCount; i++) {
            uintptr_t entPtr = readU64(itemsPtr + IL2CPP_ARRAY_DATA + (i * 8));
            if (entPtr == 0) continue;
            if (!isValidEntity(entPtr)) continue;
            
            bool dup = false;
            for (int d = 0; d < count; d++) {
                if (out[d].ptr == entPtr) { dup = true; break; }
            }
            if (dup) continue;
            
            memset(&out[count], 0, sizeof(ESPEntity));
            out[count].ptr = entPtr;
            out[count].guid = readU64(entPtr + OFF_GUID);
            out[count].hp = readI32(entPtr + OFF_HP);
            out[count].hpMax = readI32(entPtr + OFF_HP_MAX);
            out[count].camp = readI32(entPtr + OFF_CAMP);
            out[count].isDead = readBool(entPtr + OFF_IS_DEAD);
            out[count].isSelf = readBool(entPtr + OFF_IS_SELF);
            out[count].level = readI32(entPtr + OFF_LEVEL);
            out[count].pos.x = readFloat(entPtr + OFF_POS_CACHE);
            out[count].pos.y = readFloat(entPtr + OFF_POS_CACHE + 4);
            out[count].pos.z = readFloat(entPtr + OFF_POS_CACHE + 8);
            count++;
        }
        
        if (count >= 2) break;
    }
    
    if (count < 2) {
        count = 0;
        for (uintptr_t offset = 0x10; offset < 0x200 && count < maxCount; offset += 8) {
            uintptr_t entPtr = readU64(gameMap + offset);
            
            if (entPtr == 0) continue;
            if (entPtr < 0x100000000 || entPtr > 0x80000000000) continue;
            if (!isValidEntity(entPtr)) continue;
            
            bool dup = false;
            for (int d = 0; d < count; d++) {
                if (out[d].ptr == entPtr) { dup = true; break; }
            }
            if (dup) continue;
            
            memset(&out[count], 0, sizeof(ESPEntity));
            out[count].ptr = entPtr;
            out[count].guid = readU64(entPtr + OFF_GUID);
            out[count].hp = readI32(entPtr + OFF_HP);
            out[count].hpMax = readI32(entPtr + OFF_HP_MAX);
            out[count].camp = readI32(entPtr + OFF_CAMP);
            out[count].isDead = readBool(entPtr + OFF_IS_DEAD);
            out[count].isSelf = readBool(entPtr + OFF_IS_SELF);
            out[count].level = readI32(entPtr + OFF_LEVEL);
            out[count].pos.x = readFloat(entPtr + OFF_POS_CACHE);
            out[count].pos.y = readFloat(entPtr + OFF_POS_CACHE + 4);
            out[count].pos.z = readFloat(entPtr + OFF_POS_CACHE + 8);
            count++;
        }
    }
    
    if (count < 2) {
        count = 0;
        for (uintptr_t offset = 0x10; offset < 0x200 && count < maxCount; offset += 8) {
            uintptr_t entPtr = readU64(gameMap + offset);
            
            if (entPtr == 0) continue;
            if (entPtr < 0x100000000 || entPtr > 0x80000000000) continue;
            if (!isValidShowEntity(entPtr)) continue;
            
            bool dup = false;
            for (int d = 0; d < count; d++) {
                if (out[d].ptr == entPtr) { dup = true; break; }
            }
            if (dup) continue;
            
            memset(&out[count], 0, sizeof(ESPEntity));
            out[count].ptr = entPtr;
            out[count].guid = readU64(entPtr + SHOW_GUID);
            out[count].hp = readI32(entPtr + SHOW_HP);
            out[count].hpMax = readI32(entPtr + SHOW_HP_MAX);
            out[count].camp = readI32(entPtr + SHOW_CAMP);
            out[count].isDead = readBool(entPtr + SHOW_IS_DEAD);
            out[count].isSelf = readBool(entPtr + SHOW_IS_SELF);
            out[count].level = readI32(entPtr + SHOW_LEVEL);
            out[count].pos.x = readFloat(entPtr + SHOW_POS_CACHE);
            out[count].pos.y = readFloat(entPtr + SHOW_POS_CACHE + 4);
            out[count].pos.z = readFloat(entPtr + SHOW_POS_CACHE + 8);
            count++;
        }
    }
    
    return count;
}

__attribute__((constructor))
static void esp_init(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[ESPRenderer shared] start];
    });
}
