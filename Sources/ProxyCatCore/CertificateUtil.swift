//
//  File.swift
//  
//
//  Created by xiangyue on 2022/12/31.
//

import NIOSSL
import CNIOBoringSSL

/**
 CA 生成 https://devopscube.com/create-self-signed-certificates-openssl/
 
 C 实现 https://github.com/zozs/openssl-sign-by-ca/blob/master/openssl1.1/main.c
 https://github.com/warmlab/study/blob/master/openssl/x509.c
 */
let CAKeyString = """
-----BEGIN PRIVATE KEY-----
MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQDY7kQXmWQQLFC0
DEPPfcKNSSxPnxnSt2uraQxHZNBZ1rSC/MkQ0rZEYhUuF0b+RjvdI/qgC00ABkZw
j5QQkdipDZJYrbp//DaRaD7r6NWKoY7N+9g+6PLymaScv4YB9lXIjzScw0SHC32r
yCQG1kIHHAbOzv+XZTe6Ks0Po/BlhZhpBQEKkJJvVSM+W+LughAMfllGg+DCz0f/
anajO1LK6x981E7m6dfvkJ3xDHXicI0myp14K35MVeoqIf+LyIO3h55M8+gijIFk
tNEJKtB9dQcs9m2A80vWgmd13HYSDqEQZkCSwsgInnl2KDOkCyN6rK3g45HiK8CI
SwekO13BAgMBAAECggEAVmwN6ozshVjySdh9B2Olp13YblwHEKCMH3y5LJQoQTI9
NdX5UF9xx6p/n54cZV6bqM0Vor79zR2y4FMC/NrtwuOqQvPrUeOr5Z/vOVLIB/O3
Da7ghqeNakL1hpDylUOLB1yt7CoK2fYk+dPBLowbP/PVbnye7LShT+SPT0TTl822
ji0YZ/JNUMgZsO98mAziBTzIluK5bOW8+2XBm4+g4NucqY0Ee+9CG3v7EySnj7fR
qCWRWF7w8BdLpX81u5E0y7bnqwiB/erIivoCo3UFzYrwveG1+GDSWerNwpB7eOEN
zRTQ1oALBRdZado0TO2gxIa1knv+Cxa6+1saAEAWtQKBgQDwKz2+sGNmoukIQ5a0
HN5iRpGjh5dAEzXIEvwo9FCcRdRYltdjWoTrDlv/pnHhWf45pl86MbyFcq27Ps+q
HVRccA9AIJr126BkUAPU+6YoiQuB1g/ih4XhZMgMnINOZdEyMsCw6KEQ197OjgOh
AadbbTYiCy41e4tmnrEgTQaHZwKBgQDnOuOooNgjnsuaF4RTvUyM6k2k8/dwiXxc
O1qxfFmTB9gjH4Hs3N3mSxHdHvbWu6eVYdDTdI26PCB0XtOU5FSi7nF7IM4gU8Jj
e8GvtMQmqOp0VtjbQdb4RFvEzHtOO4aZ+i7kOF/sa7PtDzrClusnJnYVnQoe0wsC
hO6TmiKAlwKBgFLKlT5nD90Ry8NNiWYNjZvTN+FnnHw6IxAVe1ei4Sb963WeiiF1
0tw01wIKHrfQjhLRh4JIIvTd04X44R2DftFez+MLWl/mliP+cVO6bE0M8SqQ4Gj2
zvAkDdJLIfikoLjtRf+2Mc/cmrIZwqZ+K3MY8tBJimRlcmity+GWq+mBAoGACcp1
j1NYM5HqvxiV0tHmJuVY6k4mQQ6hRGqC+ZbxWAdyAHK6FqR3hOPS2tEP1KHXg7zD
keCSi7s2CJdnUBum9csw5OzLrZS+W2YHGoCF+bkXTFvNDOOpzZNfa2LZKcPdfDGa
wLEeZq1czgHiFBE93ceEIoAmyI1ZHv8v9vIE2fsCgYAbR/1IxwgFX8lmbGUx0Sq6
BPTFIbhZ3Y4J2TirjoB6mFErIdtsj4UzuBTHe49eHndI76OSOLFZ4z4k75WnTU89
0JS6Fcw2zLa03NSWeAlOozN0UqIcJQHNaFsyGMsQXz+1hqv0UXgeyICkdKOHJMqg
RNdhmvIWvqLFEQtbAghpPQ==
-----END PRIVATE KEY-----
"""

let CACertString = """
-----BEGIN CERTIFICATE-----
MIIC/jCCAeYCCQDpR2i4JVXCNTANBgkqhkiG9w0BAQsFADBBMRowGAYDVQQDDBFk
ZW1vLm1sb3BzaHViLmNvbTELMAkGA1UEBhMCVVMxFjAUBgNVBAcMDVNhbiBGcmFu
c2lzY28wHhcNMjIxMjI5MTQ1MTI4WhcNMjMxMjIwMTQ1MTI4WjBBMRowGAYDVQQD
DBFkZW1vLm1sb3BzaHViLmNvbTELMAkGA1UEBhMCVVMxFjAUBgNVBAcMDVNhbiBG
cmFuc2lzY28wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDY7kQXmWQQ
LFC0DEPPfcKNSSxPnxnSt2uraQxHZNBZ1rSC/MkQ0rZEYhUuF0b+RjvdI/qgC00A
BkZwj5QQkdipDZJYrbp//DaRaD7r6NWKoY7N+9g+6PLymaScv4YB9lXIjzScw0SH
C32ryCQG1kIHHAbOzv+XZTe6Ks0Po/BlhZhpBQEKkJJvVSM+W+LughAMfllGg+DC
z0f/anajO1LK6x981E7m6dfvkJ3xDHXicI0myp14K35MVeoqIf+LyIO3h55M8+gi
jIFktNEJKtB9dQcs9m2A80vWgmd13HYSDqEQZkCSwsgInnl2KDOkCyN6rK3g45Hi
K8CISwekO13BAgMBAAEwDQYJKoZIhvcNAQELBQADggEBACD0nz8DKHaMUhNKb6s8
SlezgLD2vdywNgl/eHV0J+rR6OWZ1NXm495ip0LrqO6eY9G830LrrCYaD1twsuBy
fRYigW7S8hvr+8iX47YeLVWktm0i6tlWPd7P8yV1oYmQwT0N3OGTbZ0oY5nNVayv
6iRrHI0Giy9KpwZFYzUUx70+keFtYI7bK8jGD+IWzOS2uZHkUrcrLtrIwi5aA/Cz
HlP9ADuhv2pHu/6ltkqVNvFYLj2DFEFdrG8W4rLIB2pDJdyCC8Y8T7SU9GpOAAZ7
H4rSgIcHQkf+Tv6cP4Dgp/ZKV2Qa1rOKI+7wO/3ldYR8YwVXhkt72Tr92ay6DJyi
IcM=
-----END CERTIFICATE-----
"""

let serverPrivateKeyString = """
-----BEGIN RSA PRIVATE KEY-----
MIIEpQIBAAKCAQEA1fGExjQ6GshOVPEELnv9WRGiHvQn1kogM5YZEYMLKawvUFNu
8MAga5XDs+FfR9WCdypaBUXEJCEk+qEGFpSRaJs3B5YGgpzhTJ7ug8N/b1QfXSBn
TH9AJnrbcYiLFT0ssI+9DZNuzr4cKtDhw3kBSgzrS0yikgOz67bYdw5vXRU/CyVl
YGLgk1kxkfyemKUiw89HMWAGKzR9aitqVBD6/z7jQyUW8vjhMRGkEitG46LXAxHb
QXbTNxJqaa4SNVUzot4pcZm9miNEYcak+ZvTAZHxnAOPGPU8A/lvDmcD8Qug7ga7
wIZJFMxflorXiysKWSg+PoJChQucwq5pl1KsWwIDAQABAoIBAQCdyOgRfcc0pXIP
90kMN2mb3QNiLNOMmVKyeQq3/Zun+lNSvJXffPLsJaIV8ithQThdRqDprpB/zOoG
5ecllCDBs2eccqsOfUE0Tyq9httfcf1Ho3RL2LWpK4bYbsmUum9RMFFPx+I7G76O
XUuD7KRkxq5p9HUZlx2ExG9VLxI25PEi24pgTZp72I2CBRQ8LTvKuB89KSVrf5qh
/U0Sy+7rPisG+DL2I5ZokBhYP9x/hQUciGpz0kORUWmKMEkbMMqRgZW8EifJXSgQ
7tyKyPZRN4KVlMAyCTWRGvVhnaj6EvrhdxCYg66Lq0Ro7S8p9Ui1tr/VpgY87E1G
5zE8hXIhAoGBAPFSdgvkoGMZe7KNmsntFFB5prfjbwitg2CxQ0Tk7Lfi/NAQu6mR
J9EtZfwXa35KzUaADnNEWRNsqKs0e1Cx7HicyZz3Ntmlwk23qnzu6reuOukGoRLJ
Wk/okOTAc5XeBKcmEteMzFu4Q+444lfnCHyJymysCQYoA5jUaTk3o/XzAoGBAOL0
wQiC/qzXDns+NLw0Utebi2nZ/9la4MI1JudkA4KemUOh6to2XIbK2OTVjmJ5PO1f
O5i8fBqYgSRniXPRFno/Cax951srmEhxD98Rmd7cKNa0w7rpQliZNSFLIK4RWpH9
KVJsi6Fe+x8sj96XIpJT82d4kxVNWdLeTd/bs4H5AoGBAJL47+Aqa+wvFwEV8RHO
DDM/A+S25WbZlkwLabbJ3cnYurRVnJWXTDK/fX9dHCCcmgy37RUSqVWFNeyfWAM7
eZOzma65eXRw2bfPhkv0josz17kYSn1QmGpWb/iBpWO/BgJu08bnf4bU4Lpzdpam
pKqEmP46gHx5Xkd0BmnMk1U1AoGBAMo0sr94ppsryDU5yRZdr+l1JhMbLX5kH5go
bw795rq7v2Won2vnvyxBEllfg8pspkH+9UQxuoifk3/x118ezN4ByAas7jImdzkj
srZWIjeTA7e3uiOPq5LwfYu6OdWclIs5eVV8bDNMQoUV2ODC2wRwU46+uJzkG8Fq
Wwu13QtRAoGAegLFwtxTVv+SDdCMvuSlnOTpqhIfAIwLHAGRe9vg5KDZvfoG+OZ/
DfGPJTd9iBkfl1ttBvnQTvooHm0DN82c+y6TcE4ANsxr2UsN66UpGV9N9C6B9OhU
DVA5AEnZ/yBICUD8pW/CMj3PP62QwZoMCnr225aFSiUUg0Tqy1FP/Go=
-----END RSA PRIVATE KEY-----
"""

public struct CertificateUtil {
    let caKeyRef: UnsafeMutablePointer<EVP_PKEY> =  [UInt8](CAKeyString.utf8).withUnsafeBytes { (ptr) -> UnsafeMutablePointer<EVP_PKEY> in
        let flag = 1
        let bio = CNIOBoringSSL_BIO_new_mem_buf(ptr.baseAddress!, CInt(ptr.count))!
        defer {
            CNIOBoringSSL_BIO_free(bio)
        }
        
        return withExtendedLifetime(flag) { (flag) -> UnsafeMutablePointer<EVP_PKEY> in
            return CNIOBoringSSL_PEM_read_bio_PrivateKey(bio, nil, nil, nil)
        }
    }
    
    let caCertRef = [UInt8](CACertString.utf8).withUnsafeBytes { (ptr) -> OpaquePointer? in
        let bio = CNIOBoringSSL_BIO_new_mem_buf(ptr.baseAddress, CInt(ptr.count))!
        
        defer {
            CNIOBoringSSL_BIO_free(bio)
        }
        
        return CNIOBoringSSL_PEM_read_bio_X509(bio, nil, nil, nil)
    }
    
    let serverKeyRef: UnsafeMutablePointer<EVP_PKEY> =  [UInt8](serverPrivateKeyString.utf8).withUnsafeBytes { (ptr) -> UnsafeMutablePointer<EVP_PKEY> in
        let flag = 1
        let bio = CNIOBoringSSL_BIO_new_mem_buf(ptr.baseAddress!, CInt(ptr.count))!
        defer {
            CNIOBoringSSL_BIO_free(bio)
        }
        
        return withExtendedLifetime(flag) { (flag) -> UnsafeMutablePointer<EVP_PKEY> in
            return CNIOBoringSSL_PEM_read_bio_PrivateKey(bio, nil, nil, nil)
        }
    }
    
    func addExtension(x509: OpaquePointer, nid: CInt, value: String) {
        var extensionContext = X509V3_CTX()
        
        CNIOBoringSSL_X509V3_set_ctx(&extensionContext, x509, x509, nil, nil, 0)
        let ext = value.withCString { (pointer) in
            return CNIOBoringSSL_X509V3_EXT_nconf_nid(nil, &extensionContext, nid, UnsafeMutablePointer(mutating: pointer))
        }!
        CNIOBoringSSL_X509_add_ext(x509, ext, -1)
        CNIOBoringSSL_X509_EXTENSION_free(ext)
    }
    
    func addExtension2(x509: OpaquePointer, nid: CInt, value: String) {
        var extensionContext = X509V3_CTX()
        
        CNIOBoringSSL_X509V3_set_ctx(&extensionContext, caCertRef, x509, nil, nil, 0)
        let ext = value.withCString { (pointer) in
            return CNIOBoringSSL_X509V3_EXT_nconf_nid(nil, &extensionContext, nid, UnsafeMutablePointer(mutating: pointer))
        }!
        CNIOBoringSSL_X509_add_ext(x509, ext, -1)
        CNIOBoringSSL_X509_EXTENSION_free(ext)
    }
    
    func generateCSR() -> OpaquePointer? {
        
        //  let key = CNIOBoringSSL_EVP_PKEY_new()
        //  let rsa = CNIOBoringSSL_RSA_new()
        //  let e = CNIOBoringSSL_BN_new()
        //
        
        
        //  CNIOBoringSSL_BN_set_word(e, 65537)
        //  CNIOBoringSSL_RSA_generate_key_ex(rsa, 2048, e, nil)
        //  CNIOBoringSSL_EVP_PKEY_assign_RSA(key, rsa)
        
        let key = serverKeyRef
        let req = CNIOBoringSSL_X509_REQ_new()
        CNIOBoringSSL_X509_REQ_set_pubkey(req, key)
        let name = CNIOBoringSSL_X509_REQ_get_subject_name(req)
        CNIOBoringSSL_X509_NAME_add_entry_by_txt(name, "C", MBSTRING_ASC, "US", -1, -1, 0)
        CNIOBoringSSL_X509_NAME_add_entry_by_txt(name, "ST", MBSTRING_ASC, "California", -1, -1, 0)
        CNIOBoringSSL_X509_NAME_add_entry_by_txt(name, "L", MBSTRING_ASC, "San Fransisco", -1, -1, 0)
        CNIOBoringSSL_X509_NAME_add_entry_by_txt(name, "O", MBSTRING_ASC, "MLopsHub", -1, -1, 0)
        CNIOBoringSSL_X509_NAME_add_entry_by_txt(name, "OU", MBSTRING_ASC, "MlopsHub Dev", -1, -1, 0)
        CNIOBoringSSL_X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC, "demo1.mlopshub.com", -1, -1, 0)
        
        CNIOBoringSSL_X509_REQ_sign(req, key, CNIOBoringSSL_EVP_sha256())
        return req
    }
    
    func randomSerialNumber() -> ASN1_INTEGER {
        let bytesToRead = 20
        let fd = open("/dev/urandom", O_RDONLY)
        precondition(fd != -1)
        defer {
            close(fd)
        }
        
        var readBytes = Array.init(repeating: UInt8(0), count: bytesToRead)
        let readCount = readBytes.withUnsafeMutableBytes {
            return read(fd, $0.baseAddress, bytesToRead)
        }
        precondition(readCount == bytesToRead)
        
        // Our 20-byte number needs to be converted into an integer. This is
        // too big for Swift's numbers, but BoringSSL can handle it fine.
        let bn = CNIOBoringSSL_BN_new()
        defer {
            CNIOBoringSSL_BN_free(bn)
        }
        
        _ = readBytes.withUnsafeBufferPointer {
            CNIOBoringSSL_BN_bin2bn($0.baseAddress, $0.count, bn)
        }
        
        // We want to bitshift this right by 1 bit to ensure it's smaller than
        // 2^159.
        CNIOBoringSSL_BN_rshift1(bn, bn)
        
        // Now we can turn this into our ASN1_INTEGER.
        var asn1int = ASN1_INTEGER()
        CNIOBoringSSL_BN_to_ASN1_INTEGER(bn, &asn1int)
        
        return asn1int
    }
    
    func bioToBytes(bio: UnsafeMutablePointer<BIO>?) -> [UInt8] {
        let len = CNIOBoringSSL_BIO_ctrl(bio, BIO_CTRL_PENDING, 0, nil)
        var buffer = [UInt8](repeating: 0, count: len+1)
        CNIOBoringSSL_BIO_read(bio, &buffer, Int32(len))
        
        // Ensure last value is 0 (null terminated) otherwise we get buffer overflow!
        buffer[len] = 0
        return buffer
    }
    
    public func signCertificate(forHost host: String) -> NIOSSLCertificate? {
        let csr = generateCSR()
        
        let crt: OpaquePointer = CNIOBoringSSL_X509_new()!
        CNIOBoringSSL_X509_set_version(crt, 2)
        
        // NB: X509_set_serialNumber uses an internal copy of the ASN1_INTEGER, so this is
        // safe, there will be no use-after-free.
        var serial = randomSerialNumber()
        CNIOBoringSSL_X509_set_serialNumber(crt, &serial)
        
        /* Set issuer to CA's subject. */
        CNIOBoringSSL_X509_set_issuer_name(crt, CNIOBoringSSL_X509_get_subject_name(caCertRef))
        
        /* Set validity of certificate to 2 years. */
        CNIOBoringSSL_X509_gmtime_adj(CNIOBoringSSL_X509_get_notBefore(crt), 0)
        CNIOBoringSSL_X509_gmtime_adj(CNIOBoringSSL_X509_get_notAfter(crt), 2 * 365 * 24 * 3600)
        
        /* Get the request's subject and just use it (we don't bother checking it since we generated
         * it ourself). Also take the request's public key. */
        CNIOBoringSSL_X509_set_subject_name(crt, CNIOBoringSSL_X509_REQ_get_subject_name(csr))
        let publicKey = CNIOBoringSSL_X509_REQ_get_pubkey(csr)
        CNIOBoringSSL_X509_set_pubkey(crt, publicKey)
        CNIOBoringSSL_EVP_PKEY_free(publicKey)
        
        //addExtension(x509: crt, nid: NID_subject_key_identifier, value: "hash")
        addExtension2(x509: crt, nid: NID_authority_key_identifier, value: "issuer:always")
        //addExtension(x509: crt, nid: NID_authority_key_identifier, value: "issuer:always")
        addExtension(x509: crt, nid: NID_basic_constraints, value: "CA:FALSE")
        addExtension(x509: crt, nid: NID_key_usage, value: "Digital Signature, Non Repudiation, Key Encipherment, Data Encipherment")
        addExtension(x509: crt, nid: NID_subject_alt_name, value: "DNS:demo1.mlopshub.com")
        
        
        CNIOBoringSSL_X509_sign(crt, caKeyRef, CNIOBoringSSL_EVP_sha256())
        
        let out = CNIOBoringSSL_BIO_new(CNIOBoringSSL_BIO_s_mem())
        defer { CNIOBoringSSL_BIO_free( out) }
        CNIOBoringSSL_PEM_write_bio_X509(out, crt)
        let bytes = bioToBytes(bio: out)
        //
        let cert = try? NIOSSLCertificate(bytes: bytes, format: .pem)
        print(String(cString:bytes))
        return cert
    }
}



