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
private let CAKeyString = """
-----BEGIN PRIVATE KEY-----
MIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQDUU7wJsEyHdvK6
aPfd7zhYGQODWNwT+fHzxw0c2jpbweXCHyLiHH6TwJOVfIO+yTqE0Y6I1WsGk8Lz
SfVXKF+gzHEEzMXHw0rS+26oCl8M2/mAh/FwzOcJGTj3SVMxaxg/Yvv8w7Rkkr4c
hL4lvWW/vDCYb8Ht585T1VwTMUnCsfztEH3ZPFgT5tBn9LOGh7IseAVOAovAzhEA
GuxkWCu8jYPk+JliSYwb2px0d8MgvJjAGJXbRxneciZtlW9YqSOhmB5yzvhokt9i
muhes8XaPAM3fJaibAEoEvekSr38juYd3gbwCSUiidiFFNqTjN46HSENfa95aHK2
fOFH1RuLAgMBAAECggEBALtQ1+4QO6Oyu3bazflcZu/JuYCx7w4sjljLPXU7zQpQ
J/s27tZd3wlIdqsFe1DgRCESotVyuoXF69IoaCopMxwv4HEkmkOeta8mJDxZUfuN
QTM0OzuReS1ctBXs+Vj6qxyYncgje0zS7KdKMFopGc+qHZEN3x+cRjlNXHqOHA2G
zdU1aTk/Pp0O8HdDCH+TaT8a8aXWxFxS9Z9oMq3Fb5wqbM0jJqREqJczj4vLRwSI
lEIvridE0Y6CzTKbNFQDgLb6aAu7lvJG7TSzeI8njrh4QEJkYfkAsAESxrEptTZI
YdI9ys6vifqY+VkSBdCJHnJ+AMvaPFYMmb9GVKx5bKECgYEA/YZhJeVyCRmbVlOi
rvBKrHVtRNJTZ+GHJlz8CCgg0LQDLNyP4vck+Jrd1yjbS/L/S5hMQZP6ooS6Lly6
XEJRpscxaqVG+YCEoDel7VOBUX2W7j9W+xFTBYE+MLVcIfQvLek7jeojGPb2H7Nh
6HsCDxBA6HEFNGf3QVnKci9M2BECgYEA1mZkQXFtDTOyxjbAvViL9zh8oE67TWQS
tYLiBvHQ5l9WclzpwZwssoQ7dceurYIXE0Ev7iS9eOzfrtML/QSxhMSRPWG3gKvo
01lW1mWUnBi1tZjNEGenvQ61HFqgdTOGNar+sstcr7+4qt33eYVeOwetCH7PE/4z
CoyDF7FQ9dsCgYAC2tqJNLY+B/3J0RNJ6QbOPlxGpB+wUcfV1MI5zUnhT8WhYbJ1
GddevU+2No2Ro2Dglwx0yJfP8LKwBvdKRqzoteGGk+nisWHM9BN4QrJ4GnPypt/x
39YRf80Ve1VYRImreK7lADf49f77iGeX2JrDVKmGdI9ccbdFEx/GfWXeIQKBgQDA
76OIwOnB16Qpe1w3CFfsQYjlOfST0FqFvSJp3XJ/3YuNns88y63td9GKTAeFXGwn
h6H6TFW1XHRufr1rE64sLDgHZMgdopYCm4LprL/vOM1MfhULjjwEhhe1TFjZH2TH
JvnNK/Rcs8sa+GSblskVlfLAkl0HQNntxES0LX0NwQKBgQDydSvY8CvMXiNbeROC
rkXqq+mUo2fr0G1mBmcG90HXDK1QXh8BpT+0NmLLW44at6GZIhik9g5Dd8gX3Ry1
djroAXvvd+JJWYIjo6NFsd7aZXpB7o2RT4fRchIpM0yvZdz+Fthpz/0x4lTP5pqM
i+OM06uzNgchWVzj+naS3TpqkA==
-----END PRIVATE KEY-----
"""

private let CACertString = """
-----BEGIN CERTIFICATE-----
MIIC5jCCAc4CCQD1d3GZKn6D+DANBgkqhkiG9w0BAQsFADA1MRQwEgYDVQQDDAtw
cm94eWNhdC5pbzELMAkGA1UEBhMCQ04xEDAOBgNVBAcMB0JlaWppbmcwHhcNMjMw
MTA4MTQyMjM3WhcNMjMxMjMwMTQyMjM3WjA1MRQwEgYDVQQDDAtwcm94eWNhdC5p
bzELMAkGA1UEBhMCQ04xEDAOBgNVBAcMB0JlaWppbmcwggEiMA0GCSqGSIb3DQEB
AQUAA4IBDwAwggEKAoIBAQDUU7wJsEyHdvK6aPfd7zhYGQODWNwT+fHzxw0c2jpb
weXCHyLiHH6TwJOVfIO+yTqE0Y6I1WsGk8LzSfVXKF+gzHEEzMXHw0rS+26oCl8M
2/mAh/FwzOcJGTj3SVMxaxg/Yvv8w7Rkkr4chL4lvWW/vDCYb8Ht585T1VwTMUnC
sfztEH3ZPFgT5tBn9LOGh7IseAVOAovAzhEAGuxkWCu8jYPk+JliSYwb2px0d8Mg
vJjAGJXbRxneciZtlW9YqSOhmB5yzvhokt9imuhes8XaPAM3fJaibAEoEvekSr38
juYd3gbwCSUiidiFFNqTjN46HSENfa95aHK2fOFH1RuLAgMBAAEwDQYJKoZIhvcN
AQELBQADggEBAI9e+yRI4mQmgrZOuZd88vQP9eQzFO6F1PVTMkfHtD0kEhrNpnF5
xKuYoYeO+81PlmDBl3SgIUKFmJbR0rl9ozbf0BE6kYa/ZRLZGVSOLlkaF8Xp7lAJ
JZKHQdu6XGsKHl1rvaU7l0+/MJWDB5qP44UGfFXpkLA09LQPwI29f1I0OkR1uKnm
NpKHTcIOZ0+NbqOHUsTtcKLNRBrS4VUzKaLgZ2kRFSJWCiV2zIIj730iaDHLE/in
PAuePPkE6lGFSaCh9gkt8aDQiWRCkw0ZlaFoI0anZg4xm8lnFbgUMtI9Si9hQGyu
kFLBxuTWDieeg4B8Rn+z8uweE2m4LAwQ62Y=
-----END CERTIFICATE-----
"""

private let serverPrivateKeyString = """
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEAqFLAufCyw3cK9S4dm9zrlKpzvdK+YkO3bROcq6keJ+z5wEsr
St5/hB61ZTtitH6nhkEiyegShwmTdzpeG0JKVAOARU9CxqWnWQ4Gv75kwhydr0OE
3YXKJmmksI9au5lvXyRVpPaIlmZPgcwULBKQ+eyRObHmDzsaxDELEF6121es+OJu
/BJtsZIHX30WZDQvDtFmYphmbjsM08EXYim6iB0Gb+WKjrUDqAypl5R3M9y2Nh4/
+nlaA3kXfEkcYqDwEr8fc9hOpoPbVkWlZQCk/60W49tlbtV5QhumABwBd8sHFWK1
U8VmoklmReGT8xex+Laafj69Ta36N42lA+vZ9QIDAQABAoIBAGc8Ue343Xsa0QKt
JQXKSkalAFXFInVcOOzSYX27PL6aDlfNAqFps2XR+8k50gEHyTGDU5XoGyztR5+R
kdRAJRxABXT89uSlBu2Mt8D0QhH3wRKUY7IF84T5uEN9uNVkdrUwsMJ7Xix4VX0z
MJATVw2h9TQgkwx2YKVBuxpwLDN5JHKH6fa9BXiI2oRCOqr+oNOayx9XYv9EOs2y
hiX4iOwM6g4C2HJ2lu4H2on/sA1rrOWP49vOLD+lL/jgNzMYA+YlcoAswPoBDiOA
MR/1P7UkK0ik3bG+6JThbMyyinPNmWCNme6jwYbmJNx3k9kUchgsbLW020VKUp9d
qzw7g0ECgYEA3b7nF783n03P8jo1nTgWOVk+KQLYLgDo55LfdSGMMnDfPj+PE1vg
1q5C4BWis5PO/CTt+ISF+LI60EoMsIvKpPiazjhNJ+W27Q3PsUeT+Wpz67HXK6nB
25gQTNq1TTA9HiJHgIPslBUHkBqVBTZTX1zqyyv/deIqTEuR7mK2CkUCgYEAwlM4
Oy2m8UgYgKi/qyxtXnh+Ms6cqRBsAmcrX98+Ew69ZWAA7XyzuS8q9GDBHIW4QOPU
jQL6auDY/R5Z2GcCeY5kYoU0if7kJq0z5a6TrqTVm0ijWGtxSc/c9XVfurDbtkB2
tLfQAbw0bnWo/pjyLzS8oIPYT/JzFrzVAWU94/ECgYEAtvXeww85G64eV6SDvDcc
zzC9QyVfrYV+piPfUEvf23aaHEhhCv4SI9AgybfQSQ86B32JBDaEO9EDCf0vPzP4
fenKAUEfGD5HkoyEw6dlhrO49c4E1bf5hfCP8nm6gfe9VfG+wWEYgI5hcRsdvfE3
FUYbTIv++gskD1ODEwhLX2kCgYB9l/Wu4cmVBii39tiyFCu3tB60Ta8Y4cE9KFrz
QsDG5m7od00CMOejl2WmvmXxPkegwN9eJ/+bVilIJvagk6sYzzv4JOmZCsGAcc8p
8lQGuwhHrYHNItv8fbjsd+jgK3BFcZKHKInqpS4p+ie4LTfR5L7I643B1gwmNPNi
TIHcsQKBgB9oS/r4bs2T9Ifg3+0361AOQ1IM2+5povPzZcIEpIiWszgOfC5aYwF+
/qWIIJ9Oj2tM0RjN6llruabej++BbnPa6Z8BM+9JOvn+ynWuN/P4YOaggNIxqaP8
9JljmXusRrsFkL2CEfblYSeoefb1YGB2ENuQrUa4LLujSLEej/GK
-----END RSA PRIVATE KEY-----
"""

public struct CertificateUtil {
    private let caKeyRef: UnsafeMutablePointer<EVP_PKEY> =  [UInt8](CAKeyString.utf8).withUnsafeBytes { (ptr) -> UnsafeMutablePointer<EVP_PKEY> in
        let flag = 1
        let bio = CNIOBoringSSL_BIO_new_mem_buf(ptr.baseAddress!, CInt(ptr.count))!
        defer {
            CNIOBoringSSL_BIO_free(bio)
        }
        
        return withExtendedLifetime(flag) { (flag) -> UnsafeMutablePointer<EVP_PKEY> in
            return CNIOBoringSSL_PEM_read_bio_PrivateKey(bio, nil, nil, nil)
        }
    }
    
    private let caCertRef = [UInt8](CACertString.utf8).withUnsafeBytes { (ptr) -> OpaquePointer? in
        let bio = CNIOBoringSSL_BIO_new_mem_buf(ptr.baseAddress, CInt(ptr.count))!
        
        defer {
            CNIOBoringSSL_BIO_free(bio)
        }
        
        return CNIOBoringSSL_PEM_read_bio_X509(bio, nil, nil, nil)
    }
    
    private let serverKeyRef: UnsafeMutablePointer<EVP_PKEY> =  [UInt8](serverPrivateKeyString.utf8).withUnsafeBytes { (ptr) -> UnsafeMutablePointer<EVP_PKEY> in
        let flag = 1
        let bio = CNIOBoringSSL_BIO_new_mem_buf(ptr.baseAddress!, CInt(ptr.count))!
        defer {
            CNIOBoringSSL_BIO_free(bio)
        }
        
        return withExtendedLifetime(flag) { (flag) -> UnsafeMutablePointer<EVP_PKEY> in
            return CNIOBoringSSL_PEM_read_bio_PrivateKey(bio, nil, nil, nil)
        }
    }
    
    public init() {}
    
    private func addExtension(x509: OpaquePointer, nid: CInt, value: String) {
        var extensionContext = X509V3_CTX()
        
        CNIOBoringSSL_X509V3_set_ctx(&extensionContext, x509, x509, nil, nil, 0)
        let ext = value.withCString { (pointer) in
            return CNIOBoringSSL_X509V3_EXT_nconf_nid(nil, &extensionContext, nid, UnsafeMutablePointer(mutating: pointer))
        }!
        CNIOBoringSSL_X509_add_ext(x509, ext, -1)
        CNIOBoringSSL_X509_EXTENSION_free(ext)
    }
    
    private func addExtension2(x509: OpaquePointer, nid: CInt, value: String) {
        var extensionContext = X509V3_CTX()
        
        CNIOBoringSSL_X509V3_set_ctx(&extensionContext, caCertRef, x509, nil, nil, 0)
        let ext = value.withCString { (pointer) in
            return CNIOBoringSSL_X509V3_EXT_nconf_nid(nil, &extensionContext, nid, UnsafeMutablePointer(mutating: pointer))
        }!
        CNIOBoringSSL_X509_add_ext(x509, ext, -1)
        CNIOBoringSSL_X509_EXTENSION_free(ext)
    }
    
    private func generateCSR(forHost host: String) -> OpaquePointer? {
        
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
        CNIOBoringSSL_X509_NAME_add_entry_by_txt(name, "C", MBSTRING_ASC, "CN", -1, -1, 0)
        CNIOBoringSSL_X509_NAME_add_entry_by_txt(name, "ST", MBSTRING_ASC, "Beijing", -1, -1, 0)
        CNIOBoringSSL_X509_NAME_add_entry_by_txt(name, "L", MBSTRING_ASC, "Beijing", -1, -1, 0)
        CNIOBoringSSL_X509_NAME_add_entry_by_txt(name, "O", MBSTRING_ASC, "ProxyCat", -1, -1, 0)
        CNIOBoringSSL_X509_NAME_add_entry_by_txt(name, "OU", MBSTRING_ASC, "ProxyCat Dev", -1, -1, 0)
        CNIOBoringSSL_X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC, host, -1, -1, 0)
        
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
        let csr = generateCSR(forHost: host)
        
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
        addExtension(x509: crt, nid: NID_subject_alt_name, value: "DNS:\(host)")
        
        
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
    
    public func getServerPrivateKey() -> NIOSSLPrivateKey? {
        do {
            return try NIOSSLPrivateKey(bytes: Array(serverPrivateKeyString.utf8), format: .pem)
        } catch {
            print("errro ---- \(error)")
            return nil
        }
        
    }
}


